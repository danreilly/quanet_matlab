// tcpclient.c
// client code for accessing a remote "serial port sharer" server.
// Dan Reilly 7/20/2016



#ifdef __cplusplus
#include "stdafx.h"
// NOTE: c++ complains about strcpy, and mex complains about strcpy_s!
// NOTE: c++ complains about sprintf, and mex complains about sprintf_s!
#endif


#include <Winsock2.h>
#include <Ws2tcpip.h> // for getaddrinfo?
#include <string.h>
#include <stdio.h>
#include "tcpclient.h"
// #include <windns.h>


typedef struct tcpclient_con_st {
  int    is_open;
  int    timo_ms;
  SOCKET soc;
} tcpclient_con_t;

#define MAX_CONS 8
static tcpclient_con_t cons[MAX_CONS]={0};
static int con_num_open=0;
static int wsa_started=0;




#define LOG_DBG  TCPCLIENT_LOG_DBG
#define LOG_WARN TCPCLIENT_LOG_WARN
#define LOG_INFO TCPCLIENT_LOG_INFO
#define LOG_ERR  TCPCLIENT_LOG_ERR
#define LOG_BUG  TCPCLIENT_LOG_BUG


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


static char log_lvl = LOG_DBG;

static tcpclient_log_func_t *log_func = 0;
int tcpclient_set_log_func(tcpclient_log_func_t *func, int new_log_lvl) {
  log_func = func;
  log_lvl = new_log_lvl;
  return 0;
}

static char *log_lvl_str[] = {"DBG", "INFO", "WARN", "ERR", "BUG"};
#define LOG_MSG_LEN (256)
static char log_msg[LOG_MSG_LEN]; // for short-term general use only
static char err_msg[LOG_MSG_LEN] = {0};
int tcpclient_log(int lvl, char *msg) {
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
    }
    my_strcpy_s(err_msg, LOG_MSG_LEN, log_msg2);
  }

  if (!log_func || (lvl < log_lvl)) return -1;

  if (lvl<TCPCLIENT_LOG_WARN)
    my_sprintf(log_msg2, LOG_MSG_LEN, "%s", msg); // reduce clutter
  else if (lvl != TCPCLIENT_LOG_ERR)
    my_sprintf(log_msg2, LOG_MSG_LEN, "%s: %s", log_lvl_str[lvl], msg);
  log_func(log_msg2);
  return -1; // always returns -1
}

char *tcpclient_get_err_msg(void) {
  return err_msg;
}


int con_get_unused() {
// returns -1 on error
  int i;
  for(i=0;i<MAX_CONS;++i) 
    if (!cons[i].is_open) return i;
  return -1;
}

tcpclient_con_t *con_get_open(int h) {
  if ((h<0)||(h>=MAX_CONS)) return NULL;
  if (!cons[h].is_open) return NULL;
  return &cons[h];
}



extern int tcpclient_set_prop_dbl(int con_h, char *name, double v) {
  tcpclient_con_t *con = con_get_open(con_h);
  if (!con) return -1;
  if (!strcmp(name,"Timeout")) // in s
    con->timo_ms = (int)(v*1000);
  else return 1;
  return 0;
}


extern int tcpclient_connect(char *ipaddr, int tcpport, int *con_h) {
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
  tcpclient_con_t *con;
  WSADATA wsadata;
  char servname[20];

  *con_h = -1;


  my_sprintf(log_msg, LOG_MSG_LEN, "connecting to socket at %s:%d", ipaddr, tcpport);
  tcpclient_log(LOG_WARN, log_msg);

  idx = con_get_unused();
  if (idx < 0) return tcpclient_log(LOG_ERR, "too many connections");
  con = &cons[idx];

  if (!wsa_started) {
    r = WSAStartup(MAKEWORD(2,2), &wsadata);
    if (r) return tcpclient_log(LOG_ERR, "wsastartup");
    wsa_started=1;
  }


#if (_WIN64)
  my_sprintf(servname, 20, "%d", tcpport);
  memset(&aiHints, 0, sizeof(struct addrinfo));
  aiHints.ai_family = AF_INET; // af_inet means ip4 only
  aiHints.ai_socktype = SOCK_STREAM; // handles only tcp and not udp
  aiHints.ai_protocol = IPPROTO_TCP;
  //  r = getaddrinfo(ipaddr, servname, &aiHints, &aiList);
  r = getaddrinfo(ipaddr, "", &aiHints, &aiList);
  if (r) {
    //    DNS_SERVICE_BROWSE_REQUEST req; // ={0}; didnt work
    //    req.Version=DNS_QUERRY_REQUEST_VERSION2;
    //    req.QuerryName="vbox2.local"
    return tcpclient_log(LOG_ERR, "getaddrinfo problem");
  }
  
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

  con->timo_ms = 1000;
  
  con->soc = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (con->soc==INVALID_SOCKET) return tcpclient_log(LOG_ERR, "socket");


  sa.sin_family = AF_INET;
  sa.sin_addr = addr;
  sa.sin_port = htons(tcpport);

  r = connect(con->soc, (SOCKADDR*)&sa, sizeof(sa));
  if (r) return tcpclient_log(LOG_ERR, "connect");
  // Note: connect will succeed if remote port is listening,
  //   even if remote process has not yet accepted it.

  r=1;
  r = setsockopt(con->soc, SOL_SOCKET, TCP_NODELAY, (char *)&r, sizeof(int));
  if (r) return tcpclient_log(LOG_ERR, "setsockopt nodelay");

  // Not sure how useful keepalive is
  r = 1;
  r = setsockopt(con->soc, SOL_SOCKET, SO_KEEPALIVE, (char *)&r, sizeof(int));
  if (r) return tcpclient_log(LOG_ERR, "setsockopt keepalive");

  ul = 1;
  ul = ioctlsocket(con->soc, FIONBIO, &ul);
  if (ul) return tcpclient_log(LOG_ERR, "ioctl");

  con->is_open=1;
  ++con_num_open;
  *con_h = idx;

  return 0;
}






int tcpclient_send(int con_h, char *buf, int *n_bytes) {
// desc: writes bytes to socket
// params: con_h = handle to socket
//         buf = bytes to write to the port
//         n_bytes = ptr to number of bytes to write.
//               set to num bytes written
// note: You can use this to write character zero to the port
// returns: 0 on success, non-zero on error
  int xfer, r;
  tcpclient_con_t *con = con_get_open(con_h);
  if (!con) {
    *n_bytes=0;
    return -1;
  }
  my_sprintf(log_msg, LOG_MSG_LEN, "wr %d", *n_bytes);
  tcpclient_log(LOG_DBG, log_msg);
  r = send(con->soc, buf, *n_bytes, 0);
  if (r==SOCKET_ERROR) {
    *n_bytes=0;
    return tcpclient_log(LOG_ERR, "send");
  }
  *n_bytes = r;
  return 0;
}

int tcpclient_recv(int con_h, char *buf, int *n_bytes) {
// returns 0 on success
  int l, r, ll=*n_bytes, lr=0, timo_ms=0;
  char *p=buf;
  tcpclient_con_t *con = con_get_open(con_h);
  if (!con) {
    *n_bytes=0;
    return -1;
  }
  while(ll) {
    r = recv(con->soc, p, ll, 0);
    if (!r) {// connection closed gracefully
      *n_bytes = lr;
      return tcpclient_log(LOG_WARN, "connection closed");
    }
    if (r==SOCKET_ERROR) {
      r = WSAGetLastError();
      if (r==WSAEWOULDBLOCK) {
	++timo_ms;
	Sleep(1); // 1 ms
	if (timo_ms < con->timo_ms) continue;
        break;
      }else {
        *n_bytes = lr;        
	return tcpclient_log(LOG_ERR, "recv()");
      }
    }
    p  += r;
    lr += r;
    ll -= r;
  }
  *n_bytes = lr;
  return 0;
}


int tcpclient_disconnect(int con_h) {
// desc: disconnects from server
// params: con_h = handle to connection to server
// returns: 0 on success, non-zero on error
  int r, e;
  tcpclient_con_t *con;
  con = con_get_open(con_h);
  tcpclient_log(LOG_WARN, "disconnecting");
  if (!con) return -1;

  if (shutdown(con->soc, SD_SEND)) // sends a TCP "FIN"
    tcpclient_log(LOG_ERR, "shutdown");

  /* Just slam the socket shut
  for(i=0; i<200; ++i) {
    r = recv(soc, (void *)pkt, TCPCLIENT_MAX_PKT_LEN, 0);
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
  //  if (!con_num_open) {
  //    WSACleanup();
  //    wsa_started=0;
  //  }
  return 0;
}

int tcpclient_disconnect_all(void) {
  int i, e;
  tcpclient_log(LOG_DBG, "disconnect_all");
  for(i=e=0;i<MAX_CONS;++i)
    if (cons[i].is_open)
      e = e || tcpclient_disconnect(i);
  return e?-1:0;
}
