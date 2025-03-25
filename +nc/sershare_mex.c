// sershare_mex
// Dan Reilly
// 3/24/2011

// Compile this in matlab using c.m


#include "Windows.h"
#include "mex.h"
#include "sershare.h"
#include "sershare_protocol.h"
#include <time.h>

#ifndef __TIMESTAMP__
#define __TIMESTAMP__ "?"
#endif

typedef void op_func_t(int nlhs, mxArray *plhs[],
		       int nrhs, const mxArray *prhs[]);

op_func_t op_connect, op_inq, op_mswait, op_open, op_set_prop, op_write,
  op_read, op_skip, op_close, op_disconnect, op_disconnect_all,
  op_get_err_msg;

op_func_t *ops[] = {
  /* 0 */   op_connect,
  /* 1 */   op_inq,
  /* 2 */   op_mswait,
  /* 3 */   op_open,
  /* 4 */   op_set_prop,
  /* 5 */   op_write,
  /* 6 */   op_read,
  /* 7 */   op_skip,
  /* 8 */   op_close,
  /* 9 */   op_disconnect,
  /* 10 */  op_disconnect_all,
  /* 11 */  op_get_err_msg
};

// #define OP_NUM ((sizeof(ops)/sizeof(op_func_t))
#define OP_NUM 12

HANDLE mylog_f = INVALID_HANDLE_VALUE;

int mylog(char *str) {
  DWORD i, j;
  char c='\n';
  if (mylog_f == INVALID_HANDLE_VALUE) return -1;
  j = (DWORD)strlen(str);
  WriteFile(mylog_f, str, j, &i, 0);
  WriteFile(mylog_f, &c, 1, &i, 0);
  return 0;
}

void op_connect(int nlhs, mxArray *plhs[],
		int nrhs, const mxArray *prhs[]) {
  char *ipaddr, *p;
  char tmp[80];
  int tcpport, e, con_h;
  if (nlhs!=2)
    mexErrMsgTxt("output args are [err handle]");
  if (nrhs!=2)
    mexErrMsgTxt("input args are (connect, ipaddr)");
  if (!mxIsChar(prhs[1]))
    mexErrMsgTxt("ipaddr must be a string");
  ipaddr = mxArrayToString(prhs[1]);

  // optional portnum is after a colon
  tcpport=0;
  for(p=ipaddr;*p;++p)
    if (*p==':') {
      tcpport=atoi(p+1);
      *p=0; // I hope this doesn't cause mxFree to have a mem leak!
      break;
    }

  if (mylog_f == INVALID_HANDLE_VALUE)
    mylog_f = CreateFile("sershare_client.log", GENERIC_WRITE, FILE_SHARE_READ,
		       0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if (mylog_f != INVALID_HANDLE_VALUE) {
    time_t _time;
    struct tm _tm;
#if (!_WIN64)
    struct tm *_tm_p;
#endif
    mylog("mex sershare client");
    sprintf(tmp, "  sershare protocol version %d", SERSHARE_PROTOCOL_VERSION);
    mylog(tmp);
    mylog("  sershare_mex.c");
    sprintf(tmp, "    last modified %s", __TIMESTAMP__);
    mylog(tmp);
    sprintf(tmp, "    compiled %s", __DATE__);
    mylog(tmp);
    time(&_time);
    sprintf(tmp, "  log started ");
#if (_WIN64)
    localtime_s(&_tm, &_time);
    asctime_s(tmp + strlen(tmp), 40, &_tm);
#else
    _tm_p = localtime(&_time);
    strcat(tmp, asctime(_tm_p));
#endif
    mylog(tmp);
    mylog("");
   
    // mexPrintf("writing to sershare_client.log\n");
    sershare_set_log_func((sershare_log_func_t *)mylog, 0);
  }

  con_h=99;
  e = sershare_connect(ipaddr, tcpport, &con_h);
  
  // mexPrintf("connect returned %d  con_h=%d\n", e, con_h);
  
  mxFree(ipaddr);

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = mxCreateDoubleScalar(con_h);
}


void op_open(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  char *serportname;
  int con_h, e, port_h;
  if (nlhs!=2)
    mexErrMsgTxt("open: output args are [err port_h]");
  if (nrhs!=3)
    mexErrMsgTxt("open: input args are (open, con_h, serportname)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsChar(prhs[2]))
    mexErrMsgTxt("serportname must be a string");

  con_h = (int)*mxGetPr(prhs[1]);
  serportname = mxArrayToString(prhs[2]);

  e = sershare_open(con_h, serportname, &port_h);
  
  mxFree(serportname);
  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = mxCreateDoubleScalar(port_h);
}


void op_set_prop(int nlhs, mxArray *plhs[],
	        int nrhs, const mxArray *prhs[]) {
  int con_h, port_h, e;
  char *name, *val;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=5)
    mexErrMsgTxt("input args are (set_prop, con_h, port_h, name, val)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsChar(prhs[3]))
    mexErrMsgTxt("name must be a string");
  if (!mxIsChar(prhs[4]))
    mexErrMsgTxt("val must be a string");

  con_h = (int)*mxGetPr(prhs[1]);
  port_h = (int)*mxGetPr(prhs[2]);
  name = mxArrayToString(prhs[3]);
  val = mxArrayToString(prhs[4]);

  e = sershare_set_prop(con_h, port_h, name, val);

  mxFree(val);
  mxFree(name);
  plhs[0] = mxCreateDoubleScalar(e);
}


void op_close(int nlhs, mxArray *plhs[],
	      int nrhs, const mxArray *prhs[]) {
  int con_h, e, port_h;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (close, con_h, port_h)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("port_h must be a number");
  con_h = (int)*mxGetPr(prhs[1]);
  port_h = (int)*mxGetPr(prhs[2]);
  // mexPrintf("close(%d,%d)\n", con_h, port_h);
  e = sershare_close(con_h, port_h);
  plhs[0] = mxCreateDoubleScalar(e);
}

#define RD_BUF_LEN (SERSHARE_MAX_PKT_LEN)
char rd_buf[RD_BUF_LEN];

void op_read(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int con_h, port_h, nchar, timo_ms, xfer, e, bytes_read,
      str_len, found_key, met_timo, j;
  char *p, *search_key;
  static mwSize dims[2];
  mxArray *old_str=0, *new_str;
  if (nlhs!=4)
    mexErrMsgTxt("output arg is [err str found_key met_timo]");
  if (nrhs!=6)
    mexErrMsgTxt("input args are (read, con_h, port_h, nchar, timo_ms, search_key)");

  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsDouble(prhs[3]))
    mexErrMsgTxt("nchar must be a number");
  if (!mxIsDouble(prhs[4]))
    mexErrMsgTxt("timo_ms must be a number");
  if (!mxIsChar(prhs[5]))
    mexErrMsgTxt("seach_key must be a string");

  con_h   = (int)*mxGetPr(prhs[1]);
  port_h  = (int)*mxGetPr(prhs[2]);
  nchar   = (int)*mxGetPr(prhs[3]);
  timo_ms = (int)*mxGetPr(prhs[4]);
  search_key = mxArrayToString(prhs[5]);

  // mexPrintf("nchar = %d\n", nchar);
  str_len = 0;
  while(1) {
    if (nchar < 0)
      xfer=RD_BUF_LEN;
    else {
      xfer = nchar - str_len;
      if (xfer > RD_BUF_LEN) xfer = RD_BUF_LEN;
    }
    // mexPrintf("will do sershare_read\n");
    e = sershare_read(con_h, port_h, rd_buf, xfer, timo_ms, search_key,
		      &bytes_read, &found_key, &met_timo);
    // mexPrintf("done sershare_read, e=%d  bytes_read=%d\n", e, bytes_read);
    if (e) bytes_read=0;
    dims[0]=1;  dims[1]=bytes_read+str_len; // row vector
    // mexPrintf("will createchararray %d %d\n", dims[0], dims[1]);
    new_str = mxCreateCharArray(2, dims);
    
    // mexPrintf("created size %d\n", mxGetNumberOfElements(new_str));
    p = (char *)mxGetPr(new_str);
    if (old_str) {
      // mexPrintf("will memcpy %d bytes\n", str_len*2);
      memcpy(p, (char *)mxGetPr(old_str), str_len*2);
      p += str_len*2; // it's unicode
      // mexPrintf("will destroy array\n");
      mxDestroyArray(old_str);
    }

    // mexPrintf("copy %d\n", bytes_read);
    for(j=0;j<bytes_read;++j) {
      *p++ = rd_buf[j];
      *p++ = 0; // it's unicode
    }

    old_str = new_str;
    str_len += bytes_read;
    if (   e || found_key || met_timo
	|| ((nchar>=0)&&(str_len >= nchar))) break;
  }

  mxFree(search_key);

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = new_str;
  plhs[2] = mxCreateDoubleScalar(found_key);
  plhs[3] = mxCreateDoubleScalar(met_timo);
  //  mexPrintf("mex return\n");
}

void op_get_err_msg(int nlhs, mxArray *plhs[],
	            int nrhs, const mxArray *prhs[]) {
  mxArray *s;
  //  char *m, n[512];
  if (nlhs!=1)
    mexErrMsgTxt("output arg is str");
  if (nrhs!=1)
    mexErrMsgTxt("input arg is get_err_msg");

  //  sershare_get_err_msg(n, 512);
  //  s = mxCreateString(n);
  s = mxCreateString(sershare_get_err_msg());
  if (!s) mexErrMsgTxt("mxCreateString out of mem");
  plhs[0] = s;
}


void op_skip(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int con_h, port_h, nchar, timo_ms, e, bytes_read,
    found_key, met_timo;
  char *p, *search_key;
  static mwSize dims[2];
  mxArray *old_str=0;
  if (nlhs!=4)
    mexErrMsgTxt("output is [err bytes_read found_key met_timo]");
  else if (nrhs!=6)
    mexErrMsgTxt("input args are (skip, con_h, port_h, nchar, timo_ms, search_key)");

  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsDouble(prhs[3]))
    mexErrMsgTxt("nchar must be a number");
  if (!mxIsDouble(prhs[4]))
    mexErrMsgTxt("timo_ms must be a number");
  if (!mxIsChar(prhs[5]))
    mexErrMsgTxt("seach_key must be a string");

  con_h   = (int)*mxGetPr(prhs[1]);
  port_h  = (int)*mxGetPr(prhs[2]);
  nchar   = (int)*mxGetPr(prhs[3]);
  timo_ms = (int)*mxGetPr(prhs[4]);
  search_key = mxArrayToString(prhs[5]);

  // mexPrintf("will do sershare_read\n");
  e = sershare_skip(con_h, port_h,
		    nchar, timo_ms, search_key,
		    &bytes_read, &found_key, &met_timo);
  // mexPrintf("done sershare_read, e=%d  bytes_read=%d\n", e, bytes_read);
  if (e) bytes_read=0;

  mxFree(search_key);

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = mxCreateDoubleScalar(bytes_read);
  plhs[2] = mxCreateDoubleScalar(found_key);
  plhs[3] = mxCreateDoubleScalar(met_timo);
}


void op_inq(int nlhs, mxArray *plhs[],
	    int nrhs, const mxArray *prhs[]) {
  int con_h, len, e, i, cnt;
  char *p;
  mxArray *a, *s;
  if (nlhs!=2)
    mexErrMsgTxt("output arg is [err list]");
  if (nrhs!=2)
    mexErrMsgTxt("input args are (inq, con_h)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  
  con_h = (int)*mxGetPr(prhs[1]);

  e = sershare_inq(con_h, rd_buf, RD_BUF_LEN, &len);
  if (len > RD_BUF_LEN) {
    len = RD_BUF_LEN;
    mexPrintf("BUG: increase RD_BUF_LEN in sershare_mex.c");
  }

  p = rd_buf;
  for(cnt=i=0;i<len;++i)
    if (!*p++) ++cnt;
  // mexPrintf("cnt = %d\n", cnt);

  a = mxCreateCellArray(1, &cnt);

  p = rd_buf;
  for(i=0; i<cnt; ++i) {
    s = mxCreateString(p);
    if (!s) mexErrMsgTxt("mxCreateString out of mem");
    p += strlen(p)+1;
    mxSetCell(a, i, s);
  }

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = a;
}


void op_mswait(int nlhs, mxArray *plhs[],
	       int nrhs, const mxArray *prhs[]) {
  int con_h, ms, e;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (wait, con_h, ms)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("ms must be a number");
  
  con_h = (int)*mxGetPr(prhs[1]);
  ms = (int)*mxGetPr(prhs[2]);

  e = sershare_mswait(con_h, ms);

  plhs[0] = mxCreateDoubleScalar(e);
}

void op_write(int nlhs, mxArray *plhs[],
	      int nrhs, const mxArray *prhs[]) {
  int con_h, e, port_h;
  char *str;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=4)
    mexErrMsgTxt("input args are (write, con_h, port_h, str)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsChar(prhs[3]))
    mexErrMsgTxt("str must be a string");

  con_h = (int)*mxGetPr(prhs[1]);
  port_h = (int)*mxGetPr(prhs[2]);
  str = mxArrayToString(prhs[3]);
  if (!str) mexErrMsgTxt("out of memory");
  
  e = sershare_write(con_h, port_h, str);

  mxFree(str);
  plhs[0] = mxCreateDoubleScalar(e);
}


void op_disconnect(int nlhs, mxArray *plhs[],
		   int nrhs, const mxArray *prhs[]) {
  int e, con_h;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=2)
    mexErrMsgTxt("input arg is (disconnect, con_h)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  con_h = (int)*mxGetPr(prhs[1]);
  e = sershare_disconnect(con_h);

  if (mylog_f != INVALID_HANDLE_VALUE)
    CloseHandle(mylog_f);
  mylog_f = INVALID_HANDLE_VALUE;
  plhs[0] = mxCreateDoubleScalar(e);
  
}


void op_disconnect_all(int nlhs, mxArray *plhs[],
		       int nrhs, const mxArray *prhs[]) {
  int e;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=1)
    mexErrMsgTxt("input arg is (disconnect_all)");
  e = sershare_disconnect_all();
  if (mylog_f != INVALID_HANDLE_VALUE)
    CloseHandle(mylog_f);
  mylog_f = INVALID_HANDLE_VALUE;
  plhs[0] = mxCreateDoubleScalar(e);
}



void mexFunction(int nlhs, mxArray *plhs[],
		 int nrhs, const mxArray *prhs[]) {
  int op;
  if (nrhs<1)
    mexErrMsgTxt("missing params");
  if (!mxIsDouble(prhs[0]))
    mexErrMsgTxt("operation must be a number");
  op = (int)*mxGetPr(prhs[0]);
  if ((op<0)||(op>=OP_NUM)) {
    char msg[80];
    sprintf(msg, "bad operation %d\n", op);
    mexErrMsgTxt(msg);
  }
  // mexPrintf("op %d\n", op);
  ops[op](nlhs, plhs, nrhs, prhs);
}
