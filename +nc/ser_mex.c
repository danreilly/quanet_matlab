// ser_mex
// Dan Reilly
// 11/17/2010

// Compile this in matlab using "nc.c"

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

#include "Windows.h"
#include "mex.h"
#include "ser.h"
#include <time.h>
#include <string.h>


#ifndef __TIMESTAMP__
#define __TIMESTAMP__ "?"
#endif

typedef void op_func_t(int nlhs, mxArray *plhs[],
		       int nrhs, const mxArray *prhs[]);

op_func_t op_init, op_open, op_write,
  op_read, op_skip, op_close, op_wait_ms,
  op_get_err_msg, op_cfg;

op_func_t *ops[] = {
  /* 0 */   op_init,
  /* 1 */   op_open,
  /* 2 */   op_close,
  /* 3 */   op_write,
  /* 4 */   op_read,
  /* 5 */   op_skip,
  /* 6 */   op_get_err_msg,
  /* 7 */   op_wait_ms,
  /* 8 */   op_cfg
};
#define OP_NUM (sizeof(ops)/sizeof(op_func_t *))

void op_cfg(int nlhs, mxArray *plhs[],
	    int nrhs, const mxArray *prhs[]) {
  int e, port_h, use_rts;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (cfg port_h use_rts)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("port_h must be a number");
  port_h = (int)*mxGetPr(prhs[1]);
  use_rts = (int)*mxGetPr(prhs[2]);
  e = ser_cfg_use_rts(port_h, use_rts);
  plhs[0] = mxCreateDoubleScalar(e);
}


void op_wait_ms(int nlhs, mxArray *plhs[],
	            int nrhs, const mxArray *prhs[]) {
  int ms;
  if (nlhs!=0)
    mexErrMsgTxt("no output args");
  if (nrhs!=2)
    mexErrMsgTxt("input args are (wait, ms)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("port_h must be a number");
  ms = (int)*mxGetPr(prhs[1]);

  Sleep(ms);
}


void op_get_err_msg(int nlhs, mxArray *plhs[],
	            int nrhs, const mxArray *prhs[]) {
  mxArray *s;
  char buf[512];
  if (nlhs!=1)
    mexErrMsgTxt("output arg is str");
  if (nrhs!=1)
    mexErrMsgTxt("input arg is get_err_msg");
  ser_get_last_err(buf, 512);
  s = mxCreateString(buf);
  if (!s) mexErrMsgTxt("mxCreateString out of mem");
  plhs[0] = s;
}

void my_log_func(char *s) {
  mexPrintf("LOG: %s\n", s);
}


void op_init(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  ser_set_log_func(my_log_func, SER_LOG_ERR);
  ser_init();
}

void op_open(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  char *portname, *p;
  char tmp[80];
  int e, i, port_h, baud;

  if (nlhs!=2)
    mexErrMsgTxt("output args are [err handle]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (open, portname, baud)");
  if (!mxIsChar(prhs[1]))
    mexErrMsgTxt("portname must be a string");
  p = portname = mxArrayToString(prhs[1]);

  baud = (int)mxGetScalar(prhs[2]);

  // On windows machines, com names are funny!
  if (~strncmp(portname, "COM", 3)) {
    e = sscanf(portname+3, "%d", &i);
    if ((e==1)&&(i>9)) {
      sprintf(tmp, "//./COM%d", i);
      p = tmp;
    }
  }

  port_h=99;
  e = ser_open(p, &port_h, &baud);
  // TODO: ought to return baud in case it changed.

  mxFree(portname);
  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = mxCreateDoubleScalar(port_h);
}

void op_close(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int e, port_h;
  if (nlhs!=1)
    mexErrMsgTxt("output args are [err]");
  if (nrhs!=2)
    mexErrMsgTxt("input args are (close, port_h)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("port_h must be a number");
  port_h = (int)*mxGetPr(prhs[1]);

  e = ser_close(port_h);

  plhs[0] = mxCreateDoubleScalar(e);
}


void op_write(int nlhs, mxArray *plhs[],
	      int nrhs, const mxArray *prhs[]) {
  int e, port_h;
  char *str;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if (nrhs!=3)
    mexErrMsgTxt("input args are (write, port_h, str)");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsChar(prhs[2]))
    mexErrMsgTxt("str must be a string");

  port_h = (int)*mxGetPr(prhs[1]);
  str = mxArrayToString(prhs[2]);
  if (!str) mexErrMsgTxt("out of memory");
  
  e = ser_write(port_h, str);

  mxFree(str);
  plhs[0] = mxCreateDoubleScalar(e);
}


#define RD_BUF_LEN 1024

void op_read(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int con_h, port_h, nchar, timo_ms, xfer, e, xferred,
      chars_read, found_key, met_timo, j;
  char *p, *search_keys;
  static mwSize dims[2];
  static char rd_buf[RD_BUF_LEN];
  mxArray *old_str=0, *new_str;
  LARGE_INTEGER dt, pctr1, pctr2, pcf;


  if (!QueryPerformanceFrequency(&pcf))
    mexErrMsgTxt("could not querry pcf");

  if ((nlhs<5)||(nlhs>6))
    mexErrMsgTxt("output arg is [err str bytes_read found_key met_timo]");
  if (nrhs!=5)
    mexErrMsgTxt("input args are (read, port_h, nchar, timo_ms, search_keys)");

  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("nchar must be a number");
  if (!mxIsDouble(prhs[3]))
    mexErrMsgTxt("timo_ms must be a number");
  if (!mxIsChar(prhs[4]))
    mexErrMsgTxt("seach_key must be a string");

  port_h  = (int)*mxGetPr(prhs[1]);
  nchar   = (int)*mxGetPr(prhs[2]);
  timo_ms = (int)*mxGetPr(prhs[3]);
  search_keys = mxArrayToString(prhs[4]);

  // mexPrintf("nchar = %d\n", nchar);
  chars_read = 0; // chars accumulated so far
  while(1) {
    if (nchar < 0)
      xfer=RD_BUF_LEN;
    else {
      xfer = nchar - chars_read;
      if (xfer > RD_BUF_LEN) xfer = RD_BUF_LEN;
    }
    // mexPrintf("ser_mex.read: will do ser_read timo %d\n", timo_ms);
    if (!QueryPerformanceCounter(&pctr1))
      mexErrMsgTxt("could not querry pctr");
    e = ser_read(port_h, rd_buf, xfer, timo_ms, search_keys,
		      &xferred, &found_key, &met_timo);
    if (!QueryPerformanceCounter(&pctr2))
      mexErrMsgTxt("could not querry pctr2");

    //  mexPrintf("done ser_read, e=%d  xferred=%d\n", e, xferred);
    if (e) xferred=0;
    dims[0]=1;  dims[1]=xferred+chars_read; // row vector
    new_str = mxCreateCharArray(2, dims);
    // mexPrintf("created size %d\n", mxGetNumberOfElements(new_str));

    // Note: use mxGetPr on arrays of type double only. For other types,
    //       (such as char) use mxGetData.  So says matlab docs.
    p = (char *)mxGetData(new_str);
    if (old_str) {
      // True, when this situation occurs, this copying is a bit of
      // a performance hit.  But I've hardly ever seen it occur.
      // mexPrintf("WARN: performace hit!  copy %d bytes\n", chars_read*2);
      memcpy(p, (char *)mxGetData(old_str), chars_read*2);
      p += chars_read*2; // it's unicode
      mxDestroyArray(old_str);
    }

    for(j=0;j<xferred;++j) {
      *p++ = rd_buf[j];
      *p++ = 0; // it's unicode
    }
    // mexPrintf("copy %d  p x%x\n", xferred, p);

    old_str = new_str;
    chars_read += xferred;
    if (   e || found_key || met_timo
	|| ((nchar>=0)&&(chars_read >= nchar))) break;
  }

  mxFree(search_keys);

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = new_str;
  plhs[2] = mxCreateDoubleScalar(chars_read);
  plhs[3] = mxCreateDoubleScalar(found_key);
  plhs[4] = mxCreateDoubleScalar(met_timo);

  if (nlhs==6) {
    dt.QuadPart=(pctr2.QuadPart-pctr1.QuadPart)*1000000/pcf.QuadPart;
    plhs[5] = mxCreateDoubleScalar(dt.QuadPart);
  }
}


void op_skip(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  int con_h, port_h, nchar, timo_ms, xfer, e, bytes_read,
    found_key, met_timo, j;
  char *p, *search_keys;
  static mwSize dims[2];
  mxArray *old_str=0, *new_str;
  if (nlhs!=4)
    mexErrMsgTxt("output is [err bytes_read found_key met_timo]");
  else if (nrhs!=5)
    mexErrMsgTxt("input args are (skip, port_h, nchar, timo_ms, search_keys)");

  // nchar: -1 means infinite
  // timo_ms: flush dflt is 200ms
  // search_keys: '' means no search key

  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("port_h must be a number");
  if (!mxIsDouble(prhs[2]))
    mexErrMsgTxt("nchar must be a number");
  if (!mxIsDouble(prhs[3]))
    mexErrMsgTxt("timo_ms must be a number");
  if (!mxIsChar(prhs[4]))
    mexErrMsgTxt("seach_keys must be a string");

  port_h  = (int)*mxGetPr(prhs[1]);
  nchar   = (int)*mxGetPr(prhs[2]);
  timo_ms = (int)*mxGetPr(prhs[3]);
  search_keys = mxArrayToString(prhs[4]);

  e = ser_read(port_h,
	       0, nchar, timo_ms, search_keys,
	       &bytes_read, &found_key, &met_timo);
  //  mexPrintf("SER_MEX_DBG: done op_skip, e=%d  bytes_read=%d  keylen=%d\n", e, bytes_read, strlen(search_keys));
  if (e) bytes_read=0;

  mxFree(search_keys);

  plhs[0] = mxCreateDoubleScalar(e);
  plhs[1] = mxCreateDoubleScalar(bytes_read);
  plhs[2] = mxCreateDoubleScalar(found_key);
  plhs[3] = mxCreateDoubleScalar(met_timo);
}



void mexFunction(int nlhs, mxArray *plhs[],
		 int nrhs, const mxArray *prhs[]) {
  int op;
  if (nrhs<1)
    mexErrMsgTxt("missing params");
  if (!mxIsDouble(prhs[0]))
    mexErrMsgTxt("operation must be a number");
  op = (int)*mxGetPr(prhs[0]);
  //mexPrintf("op %d\n", OP_NUM);
  if ((op<0)||(op>=OP_NUM)) {
    char msg[80];
    sprintf(msg, "bad operation %d\n", op);
    mexErrMsgTxt(msg);
  }
  // mexPrintf("op %d\n", op);
  ops[op](nlhs, plhs, nrhs, prhs);
}
