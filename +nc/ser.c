// ser.c
// 7/20/2016
// 8/2/2018 - revamped for better err msgs and fixed a buffer overwrite
// now search string is any char match

// 2/27/2019 - Added the capability for a "ser port" to be open *multiple times*.
//             Software keeps an "open counter" of the number of times it's open.
//             The underlying windows port is really open only once.
//             This abstraction makes it possible for "bridged" ports, such as when
//             a CPDS features a serial link that is connected to a PA.  Then a 
//             pa_class object can be open to the PA, while a cpds2000_class
//             object is open to the CPDS.
//
//                    USB              SERLINK
//               PC <-----> CPDS2000 <---------> PA
//
#include <Windows.h>
#include <stdio.h>
#include <io.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string.h>

//#define MEX_DBG
#ifdef MEX_DBG
#include "mex.h"
#endif

#ifndef __TIMESTAMP__
#define __TIMESTAMP__ "?"
#endif


#include "ser.h"

#define MAX_PORTS 8
#define PORT_BUF_MAX  256
#define LOG_MSG_LEN   256

static char log_lvl = SER_LOG_BUG;
static char *log_lvl_str[] = {"dbg", "warn", "ERR", "BUG"};
static ser_log_func_t *log_func = 0;
static char g_log_msg[LOG_MSG_LEN]; // for short-term general use only
static char log_buf_mem[LOG_MSG_LEN]; // for short-term general use only
static char ser_last_err[LOG_MSG_LEN];
static int log_buf_i;


typedef struct port_st {
  int    used_ctr; // number of open connections to this port
  char   name[SER_MAX_NAME_LEN+1];
  int    baud;
  int    timo_ms;

  // search for terminating string
  char   search_keys[SER_MAX_NAME_LEN+1];
  int    search_st;

  char   buf[PORT_BUF_MAX];
  int    buf_len;
  int    buf_rd_idx;
  HANDLE h;
} port_t;
port_t ports[MAX_PORTS] = {{0}, {0}, {0}, {0},
			   {0}, {0}, {0}, {0}};



int ports_new() {
// returns index of an unused port descriptor.
// -1 if none left
// TODO: mutex this?
  int i;
  for(i=0; i<MAX_PORTS; ++i) {
    if (!ports[i].used_ctr) {
      strcpy(ports[i].search_keys, "\n");
      ports[i].buf_len    = 0;
      ports[i].buf_rd_idx = 0;
      return i;
    }
  }
  return -1;
}

int ports_lookup(char *portname) {
// returns index of an unused port descriptor.
// -1 if none left
  int i;
  for(i=0; i<MAX_PORTS; ++i) {
    if (ports[i].used_ctr && !strcmp(portname, ports[i].name))
      return i;
  }
  return -1;
}


int ports_idx_valid(int port_h) {
  return ((port_h>=0) && (port_h < MAX_PORTS));
}





void ser_set_log_func(ser_log_func_t *func, int new_log_lvl) {
// desc
//    tells this code the function it should use when logging,
//    so the text can go to the console, or a log file, or whatever.
//    It's best to do this before calling any other sershare routine.
//    You only need issue this once.
//    note: Use of this routine is entirely optional.
// inputs
//    func = a pointer to a function of type ser_log_func_t
//    new_log_lvl = one of SER_LOG*
  log_func = func;
  log_lvl = new_log_lvl;
}





void ser_log_ll(int lvl, char *msg) {
// only called from ser_log! 
  if (!log_func || (lvl < log_lvl)) return;
   (*log_func)(msg);
}




static int ser_log(int port_h, int lvl, char *msg) {
// outputs
//   returns: -1 always
  static char tmp[LOG_MSG_LEN];
  if (lvl==SER_LOG_ERR)
    strcpy(ser_last_err, msg);
  if (lvl < log_lvl) return -1;
  if (port_h>=0)
    sprintf(tmp, "%s: %s: %s\n", ports[port_h].name, log_lvl_str[lvl], msg);
  else
    sprintf(tmp, "%s: %s\n", log_lvl_str[lvl], msg);


  ser_log_ll(lvl, tmp);
  if (lvl==SER_LOG_ERR) {
    int e = GetLastError();
    if (e) {
      if (e==ERROR_ACCESS_DENIED) // 5
	sprintf(tmp, "access denied (might already be open)");
      else
        sprintf(tmp, "windows err %d\n", e);
      ser_log_ll(lvl, tmp);
    }
    //    e = WSAGetLastError(); // these two always seem the same... but are they?
    //    if (e) {
    //      sprintf(tmp, "    windows socket err %d\n", e);
    //      log_print(lvl, tmp);
    //    }
  }
  return -1; // always returns -1
}






// This log_buf stuff is for debug, and prints a copy of
// all IO in hex form, 16 hex digits wide. (which is 32 visual chars wide).
// The IO data is reformatted into log_buf_mem
// before being printed out.
// All log_buf stuff is done at SER_LOG_DBG level
void log_buf_init(void) {
  int i;
  if (SER_LOG_DBG < log_lvl) return;
  for (i=0;i<52;++i) log_buf_mem[i]=' ';
  log_buf_i=0;
}

void log_buf_flush(int port_h) {
  if (SER_LOG_DBG < log_lvl) return;
  if (log_buf_i) {
    log_buf_mem[36+log_buf_i]='\n';
    log_buf_mem[37+log_buf_i]=0;
    ser_log(port_h, SER_LOG_DBG, log_buf_mem);
  }
  log_buf_init();
}

char ntohex(int n) {
  return (n<10)?(n+'0'):(n-10+'a');
}

void log_buf(int port_h, char *buf, int len) {
  char c;
  int i;
  if (SER_LOG_DBG < log_lvl) return;
  i=0;
  for(i=0;i<len;++i) {
    c = buf[i];
    log_buf_mem[2+log_buf_i*2]=ntohex(c/16);
    log_buf_mem[3+log_buf_i*2]=ntohex(c%16);
    log_buf_mem[36+log_buf_i]=(c<' ')?' ':c;
    ++log_buf_i;
    if (log_buf_i>=16)
      log_buf_flush(port_h);
  }
}




int ports_close(int port_h) {
// returns 0 on success
  ports[port_h].used_ctr = 0;
  if (!CloseHandle(ports[port_h].h))
    ser_log(port_h, SER_LOG_ERR, "CloseHandle failed"); // and cont
  return 0;
}


void ports_init(void) {
  int port_h;
  for(port_h=0; port_h<MAX_PORTS; ++port_h)
    if (ports[port_h].used_ctr) {
      ser_log(port_h, SER_LOG_ERR, "port was open");
      ports_close(port_h);
    }
}

void ser_init(void) {
  ports_init();
}




int set_port_timo(int port_h, HANDLE h, int timo_ms) {
  // returns 0 on success
  COMMTIMEOUTS cto;  
  if (timo_ms<0) timo_ms=0;
  if (!GetCommTimeouts(h, &cto)) {
    ser_log(port_h, SER_LOG_ERR, "GetCommTimeouts failed");
    return -1;
  }
  // mexPrintf("set_timo %d\n", timo_ms);

  //  printf("tos: %d %d %d\n", cto.ReadIntervalTimeout,
  // cto.ReadTotalTimeoutMultiplier, cto.ReadTotalTimeoutConstant);
  cto.ReadTotalTimeoutConstant = timo_ms; // overall time out
  cto.ReadIntervalTimeout = 1; // timo_ms?0:MAXDWORD; // max time between chars. 0 means unused.
  // If interval is maxdword and others are zero, it is non-blocking.
  cto.ReadTotalTimeoutMultiplier = 0;

  // if any char takes more than 500ms to write, that is ridiculous, so time out the write
  cto.WriteTotalTimeoutMultiplier = 500;

  if (!SetCommTimeouts(h, &cto)) {
    ser_log(port_h, SER_LOG_ERR, "SetCommTimeouts failed");
    return -1;
  }
  return 0;
}


int set_port_state(int port_h, HANDLE h, char *state_desc) {
  // returns 0 on success
  DCB dcb = {0};
  if (!GetCommState(h, &dcb)) {
    ser_log(port_h, SER_LOG_ERR, "GetCommState failed");
    return -1;
  }
  if (!BuildCommDCB(state_desc, &dcb)) {
    ser_log(port_h, SER_LOG_ERR, "BuildCommDCB failed");
    return -1;
  }
  if (!SetCommState(h, &dcb)) {
    ser_log(port_h, SER_LOG_ERR, "SetCommState failed");
    return -1;
  }
  return 0;
}


void ser_get_last_err(char *buf, int buf_len) {
  strncpy(buf, ser_last_err, buf_len-1);
  // note: if len str2 < len str1, strncpy doesn't append null
  buf[buf_len-1]=0;
}



int set_dflt_comm_state(HANDLE h) {
  DCB dcb;
  int ok;
  SecureZeroMemory(&dcb, sizeof(DCB));
  dcb.DCBlength=sizeof(DCB);
  ok=GetCommState(h, &dcb);
  if (!ok) return -1;
  dcb.ByteSize=8;
  dcb.StopBits=ONESTOPBIT;
  dcb.fParity=NOPARITY;
  dcb.fOutxCtsFlow=0;
  dcb.fOutxDsrFlow=0;
  dcb.fDtrControl=DTR_CONTROL_ENABLE;
  dcb.fRtsControl=RTS_CONTROL_ENABLE;
  ok=SetCommState(h, &dcb);
  if (!ok) return -1;
  Sleep(60); // an197 recommends delay 60ms so SetCommState has time to take effect
  return 0;
}

int set_use_rts_comm_state(HANDLE h, int use_rts) {
  DCB dcb;
  int ok;
  SecureZeroMemory(&dcb, sizeof(DCB));
  dcb.DCBlength=sizeof(DCB);
  ok=GetCommState(h, &dcb);
  if (!ok) return -1;
  if (use_rts)
    dcb.fRtsControl=RTS_CONTROL_HANDSHAKE;
  else
    dcb.fRtsControl=RTS_CONTROL_ENABLE;
  ok=SetCommState(h, &dcb);
  if (!ok) return -1;
  Sleep(60); // an197 recommends delay 60ms so SetCommState has time to take effect
  return 0;
}




int ser_open(char *portname, int *port_h_p, int *baud_p) {
// inputs
//   portname: file name of serial port to open
//   baud_p: requested baud
// outputs
//   port_h_p: on success, filled in withe the port index
//   baud_p: if port was already open, filled in with actual baud
//   returns 0 on success, non-zero on error
  int port_h, e;
  port_t *port_p;
  char *p;
  HANDLE h;
  char desc[256];
  COMMTIMEOUTS cto;  

  sprintf(g_log_msg, "open %s %d: ", portname, *baud_p);
  p = g_log_msg+strlen(g_log_msg);

  port_h=ports_lookup(portname);

  //  mexPrintf("ser_mex: open port_h %d\n", port_h);

  if (port_h>=0) {
    ++ports[port_h].used_ctr;
    //  mexPrintf("open port_h %d used %d\n", port_h, ports[port_h].used_ctr);
    *baud_p = ports[port_h].baud;
    *port_h_p = port_h;
    ser_log(port_h, SER_LOG_WARN, g_log_msg);
    return 0;
  }

  port_h = ports_new();
  if (port_h < 0) {
    sprintf(p, "out of mem");
    return ser_log(port_h, SER_LOG_BUG, g_log_msg);
  }
  port_p = &ports[port_h];

  strcpy(port_p->name, portname);
  port_p->baud = *baud_p;
  port_p->timo_ms = 2000; // added 8/13/21

  h = CreateFile(port_p->name, GENERIC_READ | GENERIC_WRITE,
 		 0, 0, OPEN_EXISTING, 0, 0);
  if (h == INVALID_HANDLE_VALUE) {
    sprintf(p, "CreateFile failed");
    return ser_log(port_h, SER_LOG_ERR, g_log_msg);
  }
  port_p->used_ctr   = 1;

  desc[0]=0;
  if (*baud_p)
    sprintf(desc, "baud=%d ", *baud_p);
  //  else
  //    sprintf(desc,
  strcat(desc, "parity=N data=8 stop=1 dtr=on rts=on idsr=off odsr=off octs=off");

  e=0;
  while (1) { // this is a loop just so we can break out of it easily

    if (set_port_state(port_h, h, desc)) {
      e=1;
      sprintf(p, "cant set port state");
      break;
    }

    if (set_dflt_comm_state(h)) {
      e=1;
      sprintf(p, "cant set dflt_comm_state");
      break;
    }


    // Microsoft doc says "Unpredictable results can occur
    // if you fail to set the time-out values."
    // In particular, if you open a serial port, and you dont set a "write timout",
    // and the first thing you do is write to it, if that device is not writable,
    // the write could hang forever! I saw it happen!
    /*
    if (!GetCommTimeouts(h, &cto)) {
      e=1;
      sprintf(p, "GetCommTimeouts failed");
      break;
    }
    */
    cto.ReadTotalTimeoutConstant = 2000; // overall time out.  Was 200. chaned 8/13/21
    cto.ReadIntervalTimeout = 1; // max time between chars. 0 means unused.
    // If interval is maxdword and others are zero, it is non-blocking.
    cto.ReadTotalTimeoutMultiplier = 0;
    // if any char takes more than 500ms to write, that is ridiculous, so time out the write
    cto.WriteTotalTimeoutMultiplier = 500;
    cto.WriteTotalTimeoutConstant = 500;

    if (!SetCommTimeouts(h, &cto)) {
      e=1;
      sprintf(p, "SetCommTimeouts failed");
      break;
    }

    break;
  }
  if (e) {
    CloseHandle(h);
    port_p->used_ctr = 0;
    return ser_log(port_h, SER_LOG_ERR, g_log_msg);
  }
  port_p->h       = h;

  *port_h_p = port_h;
  return 0;
}


int ser_close(int port_h) {
// inputs
//   port_h: indicates which port to close
// outputs
//   returns 0 on success, non-zero means err
  if (!ports_idx_valid(port_h)) {
    sprintf(g_log_msg, "close: invalid handle");
    return ser_log(-1, SER_LOG_BUG, g_log_msg);
  }
  if (ports[port_h].used_ctr<=0) {
    sprintf(g_log_msg, "close: stale handle");
    return ser_log(-1, SER_LOG_BUG, g_log_msg);
  }

  --ports[port_h].used_ctr;
  if (ports[port_h].used_ctr==0) {
    if (ports_close(port_h)) {
      sprintf(g_log_msg, "close: windows err");
      return ser_log(port_h, SER_LOG_ERR, g_log_msg);
    }
  }

  sprintf(g_log_msg, "close");
  ser_log(port_h, SER_LOG_WARN, g_log_msg);
  return 0;
}

int ser_cfg_use_rts(int port_h, int en) {
  if (!ports_idx_valid(port_h) || !ports[port_h].used_ctr)
    return ser_log(port_h, SER_LOG_ERR, "write: bad port handle");
  if (set_use_rts_comm_state(ports[port_h].h, en)) {
    sprintf(g_log_msg, "cant set use_rts");
    return ser_log(port_h, SER_LOG_ERR, g_log_msg);
  }
  return 0;
}



int ser_write(int port_h, char *str) {
// inputs
//   port_h: indicates which port to close
//   str: zero-terminated string to write to serial port
// outputs
//   returns 0 on success, non-zero means err
  int i, len;

  if (!ports_idx_valid(port_h) || !ports[port_h].used_ctr)
    return ser_log(port_h, SER_LOG_ERR, "write: bad port handle");

  len = (int)strlen(str);
  if (log_lvl <= SER_LOG_DBG) {
    sprintf(g_log_msg, "write p=%d l=%d", port_h, len);
    ser_log(port_h, SER_LOG_DBG, g_log_msg);
    log_buf_init();
    log_buf(port_h, str, len);
    log_buf_flush(port_h);
  }


  if (!WriteFile(ports[port_h].h, str, len, &i, 0))
    return ser_log(port_h, SER_LOG_ERR, "write: cant write port");

  if (i != len) {
    sprintf(g_log_msg, "write: only wrote %d out of %d", i, len);
    ser_log(port_h, SER_LOG_ERR, g_log_msg);
    return -1;
  }
  return 0;
}





int ser_read(int port_h,
	     char *buf, int max_chars, int timo_ms, char *search_keys,
	     int *chars_read, int *found_key, int *met_timo) {
// inputs
//   buf: when reading, a pointer place to put the chars that are read.
//        if buf=0, this routine will skip chars but doesn't return any
//   max_chars: size of buf, OR max number chars to read or skip
//        ~0 = infinite. 0= no chars.
//       NOTE: buf can not always be zero terminated!
//   search_keys: a short string of chars search for.  If it's an empty string
//        IE "", it won't search, and will read as many chars as possible.
//   timo_ms: timeout in milliseconds. must be 0 or positive.
// outputs
//   buf: if non-zero, this buffer gets filled in
//   chars_read: equal to number of chars read or skipped (including search key)
//   met_timo: 0=did not meet timeout, 1=met timeout
//   found_key: 0=did not find key, 1=found key
//   returns 0=succes, otherwise error
  int i, j, j_lim, k, tmp, read_so_far;
  char *p, *dst, *msg_p;
  int search_st, search_len, mask, xfer;

  *chars_read=0;
  *met_timo=0;
  *found_key=0;

  if (!buf) strcpy(g_log_msg, "skip: ");
  else strcpy(g_log_msg, "read: ");
  msg_p = g_log_msg + strlen(g_log_msg);

  if (!ports_idx_valid(port_h) || !ports[port_h].used_ctr) {
    strcpy(msg_p, "bad port handle");
    return ser_log(port_h, SER_LOG_ERR, g_log_msg);
  }
  if (!max_chars) return 0;
  if (buf && (max_chars==~0)) {
    strcpy(msg_p, "buffer size may not be infinite");
    return ser_log(port_h, SER_LOG_BUG, g_log_msg);
  }
  if (timo_ms<0) timo_ms=0;

  /* QUESTION:
  If a port is opened, the time set, then closed,
  then opened again, does it still have those timeouts? */
  
  if (timo_ms != ports[port_h].timo_ms) {
    if (set_port_timo(port_h, ports[port_h].h, timo_ms)) {
      strcpy(msg_p, "cant set port timo");
      return ser_log(port_h, SER_LOG_ERR, g_log_msg);
    }
    ports[port_h].timo_ms = timo_ms;
  }
  if (search_keys && strcmp(search_keys, ports[port_h].search_keys)) {
    i=min(SER_MAX_NAME_LEN-1,(int)strlen(search_keys));
    strncpy(ports[port_h].search_keys, search_keys, i);
    ports[port_h].search_keys[i]=0;
    //ports[port_h].search_st = 0; // start searching anew
  }
  read_so_far = 0;

  if (SER_LOG_DBG >= log_lvl) {
    sprintf(msg_p, "p=%d len=%d", port_h, max_chars);
    ser_log(port_h, SER_LOG_DBG, g_log_msg);
  }

  
  dst   = buf;

  search_st = 0;
  //  search_st  = ports[port_h].search_st; // local copy of search state
  search_keys = ports[port_h].search_keys; // empty string means don't search
  search_len = (int)strlen(search_keys);
  //search_lim = search_len?1<<(search_len-1):0; // a 1 in msb

  /*  
  sprintf(msg_p, "ser read  keys=");
  for(k=0;k<search_len;++k)
    sprintf(msg_p+strlen(msg_p), " %d", search_keys[k]);
  strcat(msg_p, "\n");
  ser_log(port_h, SER_LOG_ERR, g_log_msg);
  */
  
  log_buf_init();

  while(1) {

    // if port buffer is empty, refill it with up to PORT_BUF_MAX chars
    if (ports[port_h].buf_rd_idx >= ports[port_h].buf_len) {
      if (!ReadFile(ports[port_h].h, ports[port_h].buf,
		    PORT_BUF_MAX, &i, 0)) {
	strcpy(msg_p, "ReadFile failed");
	return ser_log(port_h, SER_LOG_ERR, g_log_msg);
      }

      if (!i) { // timo
	log_buf_flush(port_h);
	ser_log(port_h, SER_LOG_DBG, "    timo\n");

        *met_timo=1;
	*chars_read=read_so_far;
	if (buf && (read_so_far < max_chars)) *dst=0;
	return 0;
      }

      // sprintf(g_log_msg, "just read %d chars", i);
      // ser_log(port_h, SER_LOG_DBG, g_log_msg);

      ports[port_h].buf_rd_idx = 0;
      ports[port_h].buf_len = i;
    }

    xfer = max_chars - read_so_far; // bytes left to send back to requestor
    j    = ports[port_h].buf_len - ports[port_h].buf_rd_idx; // bytes left in buf
    j_lim = ((max_chars==~0)||(j<xfer))?j:xfer;

    //    printf("j_lim=%d\n", j_lim);


    // search buffer for terminating string
    search_st=0;
    if (search_len) {
      p = ports[port_h].buf + ports[port_h].buf_rd_idx;
      for(j=0; j<j_lim; ++j) {
        for(mask=k=0;k<search_len;++k)
	  if (search_keys[k]==*p) {
	    search_st=1;
	    break;
	  }
	//  	  mask = (mask>>1) | ((search_keys[k]==*p)?search_lim:0);
	//        search_st = (search_st<<1 | 1) & mask;
        if (search_st) {
	  ++j;
	  break; // & search_lim) { ++j; break; }
	}
	++p;
      }
      // ports[port_h].search_st = search_st; // save
    }else
      j = j_lim;

    while(j) {
      // copy from buffer into packet (at dst)
      p = ports[port_h].buf + ports[port_h].buf_rd_idx;      
      xfer = j;

      log_buf(port_h, p, xfer);
      if (buf) {
        memcpy(dst, p, xfer);
        dst   += xfer;
      }

      read_so_far += xfer;
      ports[port_h].buf_rd_idx += xfer;
      j = j - xfer;

      // if we just found the search key
      if (!j && search_st) {
	log_buf_flush(port_h);
	strcpy(msg_p, "_found key");
	ser_log(port_h, SER_LOG_DBG, g_log_msg);
        *found_key=1;
	*chars_read=read_so_far;
	if (buf && (read_so_far < max_chars)) *dst=0;
	return 0;
      }

      // if we've read the max num chars
      if ((max_chars != ~0) && (read_so_far >= max_chars)) {
	log_buf_flush(port_h);
	strcpy(msg_p, "maxlen");
	ser_log(port_h, SER_LOG_DBG, g_log_msg);

	if (j)
	  ser_log(port_h, SER_LOG_BUG, "read: I screwed up the rsp len");
	if (!buf) {
	  sprintf(g_log_msg, "skiped: %d", read_so_far);
	  ser_log(port_h, SER_LOG_DBG, g_log_msg);
	}
	*chars_read=read_so_far;
	ser_log(port_h, SER_LOG_DBG, "rd done");
	return 0;
      }

    }
    // printf(" buf  idx=%d  len=%d\n",ports[port_h].buf_rd_idx, ports[port_h].max_chars);
  }
}
