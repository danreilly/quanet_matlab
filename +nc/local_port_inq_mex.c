// local_port_inq.c
// Dan Reilly
//
// matlab is frustratingly slow at opening and closing serial ports,
// so dan wrote this to querry local ports.
//
// compile this in matlab using c.m
//
// Changes:
//   2/4/2011 - maxports increased to 20
//   11/12/2014 - hacked but disregard this

#include "Windows.h"
#include "mex.h"

void vfy_class(int i, const mxArray *pm, char *class) {
  char buf[80];
  if (!mxIsClass(pm, class)) {
    sprintf(buf, "ERR: param %d must be vector of %s\n", i+1, class);
    mexErrMsgTxt(buf);
  }
}


#define MAXBUF 80
#define MAXPORTS_DEF 99
#define DSIZE 20000
void mexFunction(int nlhs, mxArray *plhs[],
		 int nrhs, const mxArray *prhs[]) {
  int i, a_i=0, b_i=0, bauds_len=0, e;
  mxArray *a, *b, *s;
  char portname[16];
  wchar_t devlist[DSIZE];
  HANDLE h;
  double *bauds=0;
  int maxports=MAXPORTS_DEF;
  mwSize dim;
  if (nlhs!=2)
    mexErrMsgTxt("output arg is [list denylist]");
  if (nrhs==1) {
    vfy_class(0, prhs[0], "double");
    maxports = max(10,(int)*mxGetPr(prhs[0]));
  }else if (nrhs>1)
    mexErrMsgTxt("too many input args");
  dim = maxports;
  a = mxCreateCellArray(1, &dim);
  b = mxCreateCellArray(1, &dim);

#if 0
  i=QueryDosDeviceW(0,devlist,DSIZE);
  if (!i) {
    e=GetLastError();
    if (e) {
      mexPrintf("windows err %d\n", e);
      sprintf(devlist, "windows err %d", e);
      //   s = mxCreateString(devlist);
      // if (!s) mexErrMsgTxt("mxCreateString out of mem");
      // mxSetCell(b, b_i, s);
      // b_i++;
    }
  }else {
    int s=0,e,ii=0;
    char str[32];
    mexPrintf("Q i=%d  l=%d\n", i, _tcslen(devlist));
    mexPrintf("sz %d\n",sizeof(devlist));
    e=0;
    for(s=0;(s<i);++s) {
      if (!devlist[s]) {
        str[e]=0;
        if (strstr(str,"COM"))
          mexPrintf("%s\n", str);
        e=0;
      }else {
        str[e++]=(char)(devlist[s]&0xff);
      }
    }
    mexPrintf("\n");
  }
#endif   


  for(i=1; i<=maxports; ++i) {
    if (i<10)
      sprintf(portname, "COM%d", i);
    else
      sprintf(portname, "//./COM%d", i);
    h = CreateFile(portname, GENERIC_READ | GENERIC_WRITE,
    	  	   0, 0, OPEN_EXISTING, 0, 0);
    if (h == INVALID_HANDLE_VALUE) {
      e=GetLastError();
      if (e==ERROR_ACCESS_DENIED) {
        if (i>=10) sprintf(portname, "COM%d", i);
        s = mxCreateString(portname);
        if (!s) mexErrMsgTxt("mxCreateString out of mem");
        mxSetCell(b, b_i, s);
        b_i++;
      }
    }else {
      // mexPrintf("can open %s", portname);
      if (i>=10) sprintf(portname, "COM%d", i);
      s = mxCreateString(portname);
      if (!s) mexErrMsgTxt("mxCreateString out of mem");
      mxSetCell(a, a_i, s);
      a_i++;

      if (!CloseHandle(h))
        mexPrintf("local_port_inq_mex: CloseHandle failed");
    }
  }

  mxSetM(a, a_i);
  // does not change mem allocated to a,
  // but that will be freed when a is discarded.
  mxSetM(b, b_i);

  plhs[0] = a;
  plhs[1] = b;
}


