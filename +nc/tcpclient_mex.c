// tcpclient_mex
// Dan Reilly
// 3/24/2011

// Compile this in matlab using c.m


#include "Windows.h"
#include "mex.h"
#include "tcpclient.h"
#include <time.h>

#ifndef __TIMESTAMP__
#define __TIMESTAMP__ "?"
#endif

typedef void op_func_t(int nlhs, mxArray *plhs[],
		       int nrhs, const mxArray *prhs[]);

op_func_t op_connect, op_send, op_recv,
  op_disconnect, op_disconnect_all, op_set_prop,
  op_get_err_msg;

op_func_t *ops[] = {
  /* 0 */   op_connect,
  /* 1 */   op_send,
  /* 2 */   op_recv,
  /* 3 */   op_set_prop,
  /* 4 */   op_disconnect,
  /* 5 */   op_disconnect_all,
  /* 6 */   op_get_err_msg,
};

// #define OP_NUM ((sizeof(ops)/sizeof(op_func_t))
#define OP_NUM 7

HANDLE mylog_f = INVALID_HANDLE_VALUE;

int mylog(char *str) {
  mexPrintf("%s\n", str);
  /*
  DWORD i, j;
  char c='\n';
  if (mylog_f == INVALID_HANDLE_VALUE) return -1;
  j = (DWORD)strlen(str);
  WriteFile(mylog_f, str, j, &i, 0);
  WriteFile(mylog_f, &c, 1, &i, 0);
  */
  return 0;
}

void op_connect(int nlhs, mxArray *plhs[],
		int nrhs, const mxArray *prhs[]) {
  char *ipaddr;

  int tcpport, e, con_h;
  if (nlhs!=2)
    mexErrMsgTxt("output args are [err handle]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (connect, ipaddr, tcpport)");
  if (!mxIsChar(prhs[1]))
    mexErrMsgTxt("ipaddr must be a string");

  ipaddr = mxArrayToString(prhs[1]);
  tcpport = (int)*mxGetPr(prhs[2]);

  tcpclient_set_log_func(mylog, TCPCLIENT_LOG_ERR);


  e = tcpclient_connect(ipaddr, tcpport, &con_h);
  
  // mexPrintf("DBG: connect returned %d  con_h=%d\n", e, con_h);
  
  mxFree(ipaddr);

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = mxCreateDoubleScalar(con_h);
}




void op_set_prop(int nlhs, mxArray *plhs[],
	        int nrhs, const mxArray *prhs[]) {
  int con_h, port_h, e;
  char *name;
  double val;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=4)
    mexErrMsgTxt("input args are (set_prop, con_h, name, val)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsChar(prhs[2]))
    mexErrMsgTxt("name must be a string");
  if (!mxIsDouble(prhs[3]))
    mexErrMsgTxt("val must be a double");

  con_h = (int)*mxGetPr(prhs[1]);
  name = mxArrayToString(prhs[2]);
  val = (double)*mxGetPr(prhs[3]);

  e = tcpclient_set_prop_dbl(con_h, name, val);

  mxFree(name);
  plhs[0] = mxCreateDoubleScalar(e);
}




#define RD_BUF_LEN (2048)
char rd_buf[RD_BUF_LEN];

void op_recv(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int con_h, n_bytes, xfer, e, last, n_req, ary_len;
  char *p;
  static mwSize dims[2];
  mxArray *old_ary=0, *ary=0;
  if ((nlhs!=1)&&(nlhs!=2))
    mexErrMsgTxt("output arg is [data, err]");
  if ((nrhs!=2)&&(nrhs!=3))
    mexErrMsgTxt("input args are (read, con_h) or (read, con_h, n_bytes)");

  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if ((nrhs>2) && !mxIsDouble(prhs[2]))
    mexErrMsgTxt("n_bytes must be a number");

  con_h   = (int)*mxGetPr(prhs[1]);
  n_bytes = (nrhs==3) ? (int)*mxGetPr(prhs[2]) : -1;

  // mexPrintf("DBG: n_bytes = %d\n", n_bytes);

  ary_len = 0;
  while(1) {
    if (n_bytes < 0)
      n_req = RD_BUF_LEN;
    else {
      n_req = n_bytes - ary_len;
      if (n_req > RD_BUF_LEN) n_req = RD_BUF_LEN;
    }
    // mexPrintf("DBG: will do tcpclient_read\n");
    xfer=n_req;
    e = tcpclient_recv(con_h, rd_buf, &xfer);

    //   mexPrintf("DBG: done tcpclient_read, e=%d  bytes_read=%d\n", e, xfer);

    //    if (e) bytes_read=0;
    if (xfer) {
      dims[0]=1;  dims[1]=xfer+ary_len; // row vector
      // mexPrintf("will createchararray %d %d\n", dims[0], dims[1]);
      ary = mxCreateNumericArray(2, dims, mxUINT8_CLASS, mxREAL);
    
      // mexPrintf("created size %d\n", mxGetNumberOfElements(new_ary));
      p = (char *)mxGetData(ary);
      if (old_ary) {
        // mexPrintf("will memcpy %d bytes\n", ary_len*2);
        memcpy(p, (char *)mxGetData(old_ary), ary_len);
        p += ary_len;
        // mexPrintf("will destroy array\n");
        mxDestroyArray(old_ary);
      }
      // mexPrintf("copy %d\n", xfer);
      memcpy(p, rd_buf, xfer);
      old_ary = ary;
      ary_len += xfer;
    }
    if ( e || ((n_bytes>=0)&&(ary_len >= n_bytes))) break;
    if (xfer != n_req) break;
  }
  if (!ary) {
    dims[0]=0;  dims[1]=0;
    ary = mxCreateNumericArray(2, dims, mxUINT8_CLASS, mxREAL);
  }
  plhs[0] = ary;
  if (nlhs>1)
    plhs[1] = mxCreateDoubleScalar(e);
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

  //  tcpclient_get_err_msg(n, 512);
  //  s = mxCreateString(n);
  s = mxCreateString(tcpclient_get_err_msg());
  if (!s) mexErrMsgTxt("mxCreateString out of mem");
  plhs[0] = s;
}




void op_send(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int con_h, n_sent, port_h, err, ndim, i;
  mwSize *dims;
  char *data;
  if ((nlhs!=1)&&(nlhs!=2))
    mexErrMsgTxt("output arg is [n_sent] or [n_sent, err]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (send, con_h, data)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("con_h must be a number");
  if (!mxIsUint8(prhs[2]))
    mexErrMsgTxt("data must be uint8");

  con_h = (int)*mxGetPr(prhs[1]);
  data = (char *)mxGetData(prhs[2]);

  n_sent=mxGetNumberOfElements(prhs[2]); // product across all dimensions
  // mexPrintf("to send %d\n", n_sent);

  err = tcpclient_send(con_h, data, &n_sent);
  plhs[0] = mxCreateDoubleScalar(n_sent);
  if (nlhs>1)
    plhs[1] = mxCreateDoubleScalar(err);
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
  e = tcpclient_disconnect(con_h);

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
  e = tcpclient_disconnect_all();
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
  // mexPrintf("DBG: op %d\n", op);
  ops[op](nlhs, plhs, nrhs, prhs);
}
