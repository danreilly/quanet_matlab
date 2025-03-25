// sershare.c
// client code for accessing a remote "serial port sharer" server.
// Dan Reilly 7/20/2016



#ifdef __cplusplus
#include "stdafx.h"
// NOTE: c++ complains about strcpy, and mex complains about strcpy_s!
// NOTE: c++ complains about sprintf, and mex complains about sprintf_s!
#endif



#include <Winsock2.h>
// #include <Ws2tcpip.h>
#include <string.h>
#include "sershare_protocol.h"
#include "sershare.h"
#include <stdio.h>


// in seconds.  should never happen
#define CMD_RSP_TIMO 60

typedef struct sershare_con_st {
  int    is_open;
  SOCKET soc;
} sershare_con_t;


#define MAX_CONS 8
static sershare_con_t cons[MAX_CONS];
static int con_num_open=0;
static int wsa_started=0;

// globally allocated to save overhead
// of constant allocation and deallocation:
static char pkt_buf[SERSHARE_MAX_PKT_LEN];
static char *pkt_body=pkt_buf+sizeof(sershare_pkt_hdr_t);
static sershare_pkt_hdr_t *pkt = (sershare_pkt_hdr_t *)pkt_buf;


void my_sprintf(char *buf, int buflen, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
#ifdef __cplusplus
  vsprintf_s(buf, buflen-1, fmt, ap);
#else
  // vsprintf_s(buf, buflen-1, fmt, ap);
  vsprintf(buf, fmt, ap);
#endif
  va_end(ap);
}

// sadly, when I use strcpy_s in mex, it crashed!
void my_strcpy_s(char *dst, int buflen, char *src) {
  int sl = (int)strlen(src);
  if (sl+1 > buflen) sl = buflen-1;
  memcpy(dst, src, sl);
  dst[sl]=0;
}


void my_strcat(char *dst, int buflen, char *src) {
  int dl, sl;
  dl = (int)strlen(dst);
  sl = (int)strlen(src);
  //  printf("dl %d sl %d\n", dl, sl);
  //  mexPrintf("dl %d sl %d\n", dl, sl);
  if (dl+sl+1 > buflen) sl = buflen-dl-1;
  memcpy(dst+dl, src, sl);
  *(dst+dl+sl)=0;
}

int con_get_unused() {
// returns -1 on error
  int i;
  for(i=0;i<MAX_CONS;++i) 
    if (!cons[i].is_open) return i;
  return -1;
}
sershare_con_t *con_get_open(int h) {
  if ((h<0)||(h>=MAX_CONS)) return NULL;
  if (!cons[h].is_open) return NULL;
  return &cons[h];
}




#define LOG_DBG  SERSHARE_LOG_DBG
#define LOG_WARN SERSHARE_LOG_WARN
#define LOG_INFO SERSHARE_LOG_INFO
#define LOG_ERR  SERSHARE_LOG_ERR
#define LOG_BUG  SERSHARE_LOG_BUG


static char log_lvl = LOG_DBG;

static sershare_log_func_t *log_func = 0;
int sershare_set_log_func(sershare_log_func_t *func, int new_log_lvl) {
  log_func = func;
  log_lvl = new_log_lvl;
  return 0;
}

static char *log_lvl_str[] = {"DBG", "INFO", "WARN", "ERR", "BUG"};
#define LOG_MSG_LEN (256)
static char log_msg[LOG_MSG_LEN]; // for short-term general use only
static char err_msg[LOG_MSG_LEN] = {0};
int sershare_log(int lvl, char *msg) {
  char log_msg2[LOG_MSG_LEN];

  if (lvl==LOG_ERR) {
    int e = GetLastError();
    my_sprintf(log_msg2, LOG_MSG_LEN, "ERR: %s", msg);
    if (e) {
      char log_msg3[16];
      char errtxt[LOG_MSG_LEN];

      my_sprintf(log_msg3, 16, ": %d", e);
      my_strcat(log_msg2, LOG_MSG_LEN, log_msg3);
      FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM
		    | FORMAT_MESSAGE_MAX_WIDTH_MASK,
		    0, e, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		    (LPTSTR)errtxt, LOG_MSG_LEN, NULL);

      my_strcat(log_msg2, LOG_MSG_LEN, " ");
      my_strcat(log_msg2, LOG_MSG_LEN, errtxt);

      /*
      l = (int)strlen(log_msg2);
      for(j=0;j<l;++j) {
	c=log_msg2[j];
	if      (c<' ') log_msg2[j]=' ';
	else if (c>'z') log_msg2[j]='*';
      }
      log_msg2[l]=0;
      */

	//        my_sprintf(log_msg2, 16, "<%d>", l);
	// my_strcat(log_msg2, LOG_MSG_LEN, errtxt);
	// my_strcat(log_msg2, LOG_MSG_LEN, log_msg3);
	//        LocalFree(errtxt);

    }

    //    if (0) {
    //      l = (int)strlen(log_msg2);
    //      memcpy(err_msg, log_msg2, l);
    //      err_msg[l]=0;
    //    }else if (1)
    my_strcpy_s(err_msg, LOG_MSG_LEN, log_msg2);

  }

  if (!log_func || (lvl < log_lvl)) return -1;

  if (lvl<SERSHARE_LOG_WARN)
    my_sprintf(log_msg2, LOG_MSG_LEN, "%s", msg); // reduce clutter
  else if (lvl != SERSHARE_LOG_ERR)
    my_sprintf(log_msg2, LOG_MSG_LEN, "%s: %s", log_lvl_str[lvl], msg);
  log_func(log_msg2);
  return -1; // always returns -1
}

#if 0
int sershare_get_err_msg(char *buf, int buflen) {
  if (buflen > LOG_MSG_LEN) buflen = LOG_MSG_LEN;
  memcpy(buf, err_msg, buflen);
  buf[buflen]=0;
  return 0;
}
#else
char *sershare_get_err_msg(void) {
  return err_msg;
}
#endif





int recv_n(SOCKET soc, char *p, int n_bytes) {
// returns -1 on error.
  int r, timo, timo_ms, ll=n_bytes;
  timo = timo_ms = 0;
  while(ll) {
    r = recv(soc, p, ll, 0);
    if (!r) // connection closed gracefully
      return sershare_log(LOG_WARN, "connection closed");
    if (r==SOCKET_ERROR) {
      r = WSAGetLastError();
      if (r==WSAEWOULDBLOCK) {
	++timo_ms;
	Sleep(1); // 1 ms
	if (timo_ms < 1000) continue;
	timo_ms = 0;
	++timo;
	if (timo < CMD_RSP_TIMO) continue;
	return sershare_log(LOG_ERR, "timo: no data on socket");
      }else
	return sershare_log(LOG_ERR, "recv()");
    }
    p += r;
    ll -= r;
  }
  return 0;
}


int recv_pkt(SOCKET soc, sershare_pkt_hdr_t *pkt, int n_bytes) {
// n_bytes is max number of bytes in pkt, including header
// returns 0 on success
  int l, r;
  r = recv_n(soc, (char *)pkt, sizeof(sershare_pkt_hdr_t));
  if (r) return r;
  l = ntohs(pkt->len);
  if (l+(int)sizeof(sershare_pkt_hdr_t) > n_bytes) {
    // TODO: perhaps do something else, but I think this is right:
    my_sprintf(log_msg, LOG_MSG_LEN, " remote sent too big pkt (len=%d)\n", l);
    sershare_log(LOG_BUG, log_msg);
    return -1;
  }
  r = recv_n(soc, (char *)pkt+sizeof(sershare_pkt_hdr_t), l);
  return r;
}

int send_pkt(SOCKET soc, sershare_pkt_hdr_t *pkt) {
  int l, r;
  l = sizeof(sershare_pkt_hdr_t)+ntohs(pkt->len);
  r = send(soc, (char *)pkt, l, 0);
  if (r==SOCKET_ERROR) return sershare_log(LOG_ERR, "send");
  else if (r != l) {
    my_sprintf(log_msg, LOG_MSG_LEN, " sent %d out of %d bytes\n", r, l);
    return sershare_log(LOG_ERR, log_msg);
  }
  return 0;
}


static int sershare_con(sershare_con_t *con) {
// returns 0=ok, -1=err
  int r;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_CONREQ);
  pkt->len     = htons(2);
  sershare_log(LOG_WARN, "con req");
  *(short *)pkt_body = htons(SERSHARE_PROTOCOL_VERSION);
  if (send_pkt(con->soc, pkt))
    return sershare_log(LOG_ERR, "cant send con req");
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN))
    return sershare_log(LOG_ERR, "cant rcv con rsp");
  r = htons(pkt->len);
  if (r<2) return sershare_log(LOG_ERR, "bad con rsp");
  r = ntohs(*(short *)pkt_body);
  if (r!=SERSHARE_PROTOCOL_VERSION) {
    sprintf(log_msg, "server uses different protocol version (%d)", r);
    return sershare_log(LOG_ERR, log_msg);
  }
  return 0;
}


extern int sershare_connect(char *ipaddr, int tcpport, int *con_h) {
// desc: connects to server, returns a handle for future access.
// params: ipaddr = ip address of form xx.xx.xx.xx or other
//   tcpport = tcp port (if 0, it uses default)
//   con_h = set to new handle to server.  set to -1 on failure.
// returns: 0=succes, -1 = error
  int r, idx;
  unsigned long ul;
  BOOL opt_true=TRUE;
#if (_WIN64)
  struct addrinfo aiHints, *aiList=0, *p;
#endif
  struct in_addr addr;
  struct sockaddr_in sa, *sa_p;
  sershare_con_t *con;
  WSADATA wsadata;
  char servname[20];

  *con_h = -1;

  if (!tcpport) tcpport=SERSHARE_TCPPORT;
  my_sprintf(log_msg, LOG_MSG_LEN, "connecting to server at %s:%d", ipaddr, tcpport);
  sershare_log(LOG_WARN, log_msg);

  idx = con_get_unused();
  if (idx < 0) return sershare_log(LOG_ERR, "too many connections");

  if (!wsa_started) {
    r = WSAStartup(MAKEWORD(2,2), &wsadata);
    if (r) return sershare_log(LOG_ERR, "wsastartup");
    wsa_started=1;
  }

#if (_WIN64)
  my_sprintf(servname, 20, "%d", tcpport);
  memset(&aiHints, 0, sizeof(struct addrinfo));
  aiHints.ai_family = AF_INET;
  aiHints.ai_socktype = SOCK_STREAM;
  aiHints.ai_protocol = IPPROTO_TCP;
  r = getaddrinfo(ipaddr, servname, &aiHints, &aiList);
  if (r) return sershare_log(LOG_ERR, "getaddrinfo problem");
  p = aiList;
  while(p) {
    // p->ai_addrlen
    // p->ai_addr is (struct sockaddr *)
    sa_p = (struct sockaddr_in *)p->ai_addr;
    // inet_ntoa(struct in_addr) converts struct in_addr to asci string.
    sprintf(log_msg, "  ipaddr resolved to %s\n", inet_ntoa(sa_p->sin_addr));
    log_func(log_msg);

    memcpy(&addr.s_addr, &sa_p->sin_addr, sizeof(struct in_addr));

    p = p->ai_next;
    break;
  }
  freeaddrinfo(aiList);
#else
  addr.s_addr = inet_addr(ipaddr); // convert string to struct in_addr 
#endif

  con = &cons[idx];

  
  con->soc = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (con->soc==INVALID_SOCKET) return sershare_log(LOG_ERR, "socket");


  sa.sin_family = AF_INET;
  sa.sin_addr = addr;
  sa.sin_port = htons(tcpport);

  r = connect(con->soc, (SOCKADDR*)&sa, sizeof(sa));
  if (r) return sershare_log(LOG_ERR, "connect");
  // Note: connect will succeed if remote port is listening,
  //   even if remote process has not yet accepted it.

  r=1;
  r = setsockopt(con->soc, SOL_SOCKET, TCP_NODELAY, (char *)&r, sizeof(int));
  if (r) return sershare_log(LOG_ERR, "setsockopt nodelay");

  // Not sure how useful keepalive is
  r = 1;
  r = setsockopt(con->soc, SOL_SOCKET, SO_KEEPALIVE, (char *)&r, sizeof(int));
  if (r) return sershare_log(LOG_ERR, "setsockopt keepalive");

  ul = 1;
  ul = ioctlsocket(con->soc, FIONBIO, &ul);
  if (ul) return sershare_log(LOG_ERR, "ioctl");

  con->is_open=1;
  ++con_num_open;
  *con_h = idx;

  if (sershare_con(con)) {
    sershare_disconnect(idx);
    return -1;
  }

  return 0;
}


/*
void print_pkt(sershare_pkt_hdr_t *pkt) {
  char *pkt_body, *p;
  int t, len, i;
  t   = ntohs(pkt->pkttype);
  len = ntohs(pkt->len);
  pkt_body = (char *)pkt + sizeof(sershare_pkt_hdr_t);
  switch(t) {
    case SERSHARE_PKTTYPE_INQREQ: 
      printf("inqreq\n");
      break;

    case SERSHARE_PKTTYPE_SETPROPREQ:
      printf("setprop");
      if (len>=2) {
        t = ntohs(*(short *)pkt_body);
        printf(" %d", t);
      }else printf(" ???");
      printf(" ");
      for(i=2; i<len; ++i) {
	if (pkt_body[i]) printf("%c", pkt_body[i]);
	else if (i<len-1) printf(" = ");
      }
      printf("\n");
      break;

    case SERSHARE_PKTTYPE_WRITEREQ:
      printf("writereq");
      if (len>=2) {
        t = ntohs(*(short *)pkt_body);
        printf(" %d", t);
      }else printf(" ???");
      printf(" \"");
      for(i=2;i<len;++i) {
	if (pkt_body[i]<' ') printf("\\x%02X", pkt_body[i]);
	else printf("%c", pkt_body[i]);
      }
      printf("\"\n");
      break;

    case SERSHARE_PKTTYPE_READDONERSP:
    case SERSHARE_PKTTYPE_READTIMORSP:
    case SERSHARE_PKTTYPE_READCONTRSP:
    case SERSHARE_PKTTYPE_READTERMRSP:
      printf("readrsp \"");
      for(i=0;i<len;++i) {
	if (pkt_body[i]<' ') printf("\\x%02X", pkt_body[i]);
	else printf("%c", pkt_body[i]);
      }
      printf("\"\n");
      break;

    case SERSHARE_PKTTYPE_INQRSP:
      printf("inqrsp\n");
      p=pkt_body;
      while(len) {
	printf("  %s\n", p);
	len -= strlen(p)+1;
	p   += strlen(p)+1;
      }
      break;
    case SERSHARE_PKTTYPE_FAILRSP:
      printf("failrsp\n");
      break;
    case SERSHARE_PKTTYPE_OKRSP:
      printf("okrsp\n");
      break;
    case SERSHARE_PKTTYPE_MSWAITREQ:
      printf("mswait");
      goto PRINT_SHORT;
    case SERSHARE_PKTTYPE_OPENRSP:
      printf("openrsp");
      goto PRINT_SHORT;
    case SERSHARE_PKTTYPE_CLOSEREQ:
      printf("closereq");
      goto PRINT_SHORT;
    PRINT_SHORT:
      if (len==2) {
        t = ntohs(*(short *)pkt_body);
        printf(" %d\n", t);
      }else printf(" ???\n");
      break;
    default:
      printf("type %d len %d\n", t, len);
  }
}
*/


int sershare_inq(int con_h, char *buf, int buf_len, int *rsp_len) {
// desc: causes server to figure out which of its serial ports can
//   be opened.  The server responds with a list of concatenated
//   null-terminated strings.  This response is put into buf, and
//   possibly truncated. If truncated, the last string will still be
//   null-terminated.
// params: con_h = handle to connection to server
//         buf = filled in with list of ports
//         buf_len = length of buf.
//         rsp_len = if bigger than buf_len, means rsp was truncated
// returns: 0=succes, -1=err
  int j;
  sershare_con_t *con = con_get_open(con_h);
  *rsp_len = 0;
  if (!con) return -1;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_INQREQ);
  pkt->len     = htons(0);
  if (send_pkt(con->soc, pkt)) return -1;
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
  j = htons(pkt->len);
  if (j<0) return -1;
  *rsp_len = j;
  memcpy(buf, pkt_body, (j>buf_len)?buf_len:j);
  if (j>buf_len) *(buf+buf_len-1) = 0;
  return 0;
}


int sershare_mswait(int con_h, int ms) {
// desc: causes server to wait specified number of ms
// params: con_h = handle to connection to server
//         ms = number of ms
// returns: 0=succes, -1=err
  sershare_con_t *con = con_get_open(con_h);
  if (!con) return -1;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_MSWAITREQ);
  pkt->len     = htons(sizeof(int));
  *(int *)pkt_body = htonl(ms);
  if (send_pkt(con->soc, pkt)) return -1;
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
  if (ntohs(pkt->pkttype)!=SERSHARE_PKTTYPE_OKRSP) return -1;
  return 0;
}


int sershare_open(int con_h, char *serportname, int *port_h) {
// desc: tells server to attempt to open named serial port on
//       that machine.
// params: con_h = handle to connection to server
//         serportname = name of serial port, such as "COM1"
//         port_h = handle to newly opened port.
// returns: 0=succes, -1=err
  int j;
  sershare_con_t *con = con_get_open(con_h);
  *port_h = -1; // invalid port in case open fails
  if (!con) return -1;

  my_sprintf(log_msg, LOG_MSG_LEN, "open %s", serportname);
  sershare_log(LOG_DBG, log_msg);

  pkt->pkttype = htons(SERSHARE_PKTTYPE_OPENREQ);
  j = strlen(serportname);
  memcpy(pkt_body, serportname, j);
  pkt->len = htons(j);

  if (send_pkt(con->soc, pkt)) return -1;
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
  if (ntohs(pkt->pkttype) != SERSHARE_PKTTYPE_OPENRSP) return -1;
  *port_h = ntohs(*(short *)pkt_body);
  return 0;
}

int sershare_set_prop(int con_h, int port_h, char *prop_name, char *prop_val) {
// desc: sets a property about a remote serial port
// params: con_h = handle to connection to server
//         port_h = hanldle to remote serial port
//         prop_name = name of property
//         prop_val = value of property
//  See server source code to find out what
//  properties are currently implemented.
  int l;
  sershare_con_t *con = con_get_open(con_h);
  if (!con) return -1;
  l = 2;
  memcpy(pkt_body+l, prop_name, strlen(prop_name)+1);
  l += strlen(prop_name) + 1;
  memcpy(pkt_body+l, prop_val, strlen(prop_val)+1);
  l += strlen(prop_val) + 1;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_SETPROPREQ);
  pkt->len = htons(l);

  my_sprintf(log_msg, LOG_MSG_LEN, "set_prop: ");
  if (log_lvl <= LOG_DBG) {
    int r, k;
    char c, *p;
    r=2;
    p = log_msg + strlen(log_msg);
    for(k=0;k<2;++k) {
      for(;r<l;++r) {
	c = *(char *)(pkt_body+r);
	if (!c) break;
	if (c>' ') *p++ = c;
	else {
	  *p++='\\';
	  *p++=(c/10)+'0';
	  *p++=(c%10)+'0';
	}
      }
      ++r;
      if (!k) *p++='=';
    }
    *p++=0;
    sershare_log(LOG_DBG, log_msg);
  }

  if (send_pkt(con->soc, pkt)) return sershare_log(LOG_DBG, "set_prop: snd fail");
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
  // print_pkt(pkt);
  if (ntohs(pkt->pkttype)!=SERSHARE_PKTTYPE_OKRSP) {
    sprintf(log_msg, "set_prop: bad rsp = %d", ntohs(pkt->pkttype));
    return sershare_log(LOG_DBG, log_msg);
  }
  return 0;
}


int sershare_write_n(int con_h, int port_h, char *buf, int len) {
// desc: writes bytes to a remote serial port
// params: con_h = handle to connection to server
//         buf = bytes to write to the port
//         len = number of bytes to write
//         str = a null-terminated string to write to port
// note: You can use this to write character zero to the port
// returns: 0 on success, non-zero on error
  int xfer;
  sershare_con_t *con = con_get_open(con_h);
  if (!con) return -1;

  while(len) {
    xfer = len;
    if (xfer > SERSHARE_MAX_BODY_LEN-2)
      xfer = SERSHARE_MAX_BODY_LEN-2;

    pkt->pkttype = htons(SERSHARE_PKTTYPE_WRITEREQ);
    pkt->len     = htons(2+xfer);
    *(short *)pkt_body = htons(port_h);
    memcpy(pkt_body+2, buf, xfer);
    my_sprintf(log_msg, LOG_MSG_LEN, "wr %d", xfer);
    sershare_log(LOG_DBG, log_msg);
    if (send_pkt(con->soc, pkt)) return -1;
    if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
    if (ntohs(pkt->pkttype)!=SERSHARE_PKTTYPE_OKRSP) return -1;
    buf += xfer;
    len -= xfer;
  }
  return 0;
}

int sershare_write(int con_h, int port_h, char *str) {
// desc: writes a string to a remote serial port
// params: con_h = handle to connection to server
//         port_h = handle to remot port
//         str = a null-terminated string to write to port
// note: This does not write the zero character at the end of the string.
//       You can't use this routine to write character zero.
// returns: 0 on success, non-zero on error
  return sershare_write_n(con_h, port_h, str, strlen(str));
}

int sershare_skip(int con_h, int port_h,
		  int max_len, int timo_ms, char *search_key,
		  int *bytes_read, int *found_key, int *met_timo) {
// desc: causes server to read from a remote serial port and discard data
// params: con_h = handle to connection to server
//         port_h = handle to remote port
//         max_len = maximum num of chars to read
//         timo_ms = timeout in ms (~0 means never timeout)
//         search_key = char string to search for. (null ptr means use prev)
//         bytes_read = set to num bytes skipped
//         found_key = set to 1 if read ended because of terminator match
// returns: 0 on success, non-zero on error
  int l, r, pkttype;
  sershare_con_t *con = con_get_open(con_h);
  *bytes_read = *found_key = 0;
  if (!con) return -1;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_SKIPREQ);
  pkt->len     = htons(10);
  *(short *)pkt_body   = htons(port_h);
  *(int *)(pkt_body+2) = htonl(max_len);
  *(int *)(pkt_body+6) = htonl(timo_ms);
  if (search_key) {
    l = strlen(search_key);
    my_sprintf(log_msg, LOG_MSG_LEN, "skip key=%d", search_key[0]);
    sershare_log(LOG_DBG, log_msg);
    memcpy(pkt_body+10, search_key, l+1);
    pkt->len = htons(10+l+1);
  }
  if (send_pkt(con->soc, pkt)) return -1;
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
  pkttype = ntohs(pkt->pkttype);
  r =	   (pkttype == SERSHARE_PKTTYPE_READTERMRSP)
        || (pkttype == SERSHARE_PKTTYPE_READDONERSP)
	|| (pkttype == SERSHARE_PKTTYPE_READTIMORSP);
  if (!r) return sershare_log(LOG_BUG, "bad skip rsp");

  l = ntohs(pkt->len);
  if (l != 4) {
    my_sprintf(log_msg, LOG_MSG_LEN, "skiprsp len=%d", l);
    sershare_log(LOG_BUG, log_msg);
  }

  *found_key = (pkttype == SERSHARE_PKTTYPE_READTERMRSP);
  *met_timo  = (pkttype == SERSHARE_PKTTYPE_READTIMORSP);
  *bytes_read = ntohl(*(int *)pkt_body);

  my_sprintf(log_msg, LOG_MSG_LEN, "skiprsp: read=%d found=%d timo=%d",
	     *bytes_read, *found_key, *met_timo);
  sershare_log(LOG_DBG, log_msg);
  return 0;
}

int sershare_read(int con_h, int port_h, char *buf, int buf_len,
		  int timo_ms, char *search_key,
		  int *bytes_read, int *found_key, int *met_timo) {
// desc: reads from a remote serial port
// params: con_h = handle to connection to server
//         port_h = handle to remot port
//         buf = filled with characters read from port
//         buf_len = maximum num of chars to read
//         timo_ms = timeout in ms (~0 means never timeout)
//         search_key = char string to search for. (null ptr means no search)
//         found_key = set to 1 if read ended because of terminator match
// returns: 0 on success, non-zero on error
// NOTE: bytes read is not restricted by the underlying protocol.
//       (that is, it can be bigger than SERSHARE_MAX_PKT_LEN).
  int l, r, pkttype, br;
  sershare_con_t *con = con_get_open(con_h);
  char *p = buf;

  *bytes_read = *found_key = 0;
  if (!con) return -1;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_READREQ);
  pkt->len     = htons(10);
  *(short *)pkt_body   = htons(port_h);
  *(int *)(pkt_body+2) = htonl(buf_len);
  *(int *)(pkt_body+6) = htonl(timo_ms);
  if (search_key) {
    l = strlen(search_key);
    memcpy(pkt_body+10, search_key, l+1);
    pkt->len = htons(11+l);
  }

  my_sprintf(log_msg, LOG_MSG_LEN, "readreq port_h=%d,len=%d,timo=%d", port_h, buf_len, timo_ms);
  sershare_log(LOG_DBG, log_msg);
  
  if (send_pkt(con->soc, pkt)) return -1;

  br=0;
  while(1) {
    if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
    pkttype = ntohs(pkt->pkttype);
    r =    (pkttype == SERSHARE_PKTTYPE_READCONTRSP)
	|| (pkttype == SERSHARE_PKTTYPE_READTERMRSP)
        || (pkttype == SERSHARE_PKTTYPE_READDONERSP)
	|| (pkttype == SERSHARE_PKTTYPE_READTIMORSP);
    if (!r) return sershare_log(LOG_BUG, "bad read rsp");
    l = ntohs(pkt->len);

    my_sprintf(log_msg, LOG_MSG_LEN, "readrsp: type=%d len=%d\n", pkttype, l);
    sershare_log(LOG_DBG, log_msg);

    memcpy(p, pkt_body, l);
    p  += l;
    br += l;
    if (pkttype != SERSHARE_PKTTYPE_READCONTRSP) break;
  }
  *found_key = (pkttype == SERSHARE_PKTTYPE_READTERMRSP);
  *met_timo  = (pkttype == SERSHARE_PKTTYPE_READTIMORSP);
  *bytes_read = br;
  return 0;
}

int sershare_close(int con_h, int port_h) {
// desc: closes a remote serial port
// params: con_h = handle to connection to server
//         port_h = handle to remote port
// returns: 0 on success, non-zero on error
  sershare_con_t *con = con_get_open(con_h);
  if (!con) return -1;
  my_sprintf(log_msg, LOG_MSG_LEN, "close %d", port_h);
  sershare_log(LOG_DBG, log_msg);
  pkt->pkttype = htons(SERSHARE_PKTTYPE_CLOSEREQ);
  pkt->len     = htons(2);
  *(short *)pkt_body = htons(port_h);
  if (send_pkt(con->soc, pkt)) return -1;
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) return -1;
  // print_pkt(pkt);
  if (ntohs(pkt->pkttype)!=SERSHARE_PKTTYPE_OKRSP) return -1;
  return 0;
}

int sershare_disconnect(int con_h) {
// desc: disconnects from server
// params: con_h = handle to connection to server
// returns: 0 on success, non-zero on error
  int r, e;
  sershare_con_t *con;
  con = con_get_open(con_h);
  sershare_log(LOG_WARN, "disconnecting");
  if (!con) return -1;
  pkt->pkttype = htons(SERSHARE_PKTTYPE_EXITREQ);
  pkt->len     = htons(0);

  e = send_pkt(con->soc, pkt);
  if (recv_pkt(con->soc, pkt, SERSHARE_MAX_PKT_LEN)) e = -1;
  // print_pkt(pkt);
  if (ntohs(pkt->pkttype)!=SERSHARE_PKTTYPE_OKRSP) e = -1;
  if (e)
    sershare_log(LOG_WARN, "server responded badly to disconnect");

  if (shutdown(con->soc, SD_SEND)) // sends a TCP "FIN"
    sershare_log(LOG_ERR, "shutdown");

  /* Just slam the socket shut
  for(i=0; i<200; ++i) {
    r = recv(soc, (void *)pkt, SERSHARE_MAX_PKT_LEN, 0);
    if (r==SOCKET_ERROR) {
      r = WSAGetLastError();
      if (r!=WSAEWOULDBLOCK) {
	printf("ERR %d\n", r);
	break;
      }
    }
    Sleep(100);
  }
  printf("i=%d\n", i);
  */

  closesocket(con->soc);
  con->is_open=0;
  --con_num_open;
  if (!con_num_open) {
    WSACleanup();
    wsa_started=0;
  }
  return 0;
}

int sershare_disconnect_all(void) {
  int i, e;
  sershare_log(LOG_DBG, "disconnect_all");
  for(i=e=0;i<MAX_CONS;++i)
    if (cons[i].is_open)
      e = e || sershare_disconnect(i);
  return e?-1:0;
}
