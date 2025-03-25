// pm100d_mex.c
// Dan Reilly
// 5/25/2017

// Compile this in matlab using nc.pm100d_compile.m


#include "Windows.h"
#include "mex.h"
#include "ser.h"
#include <time.h>
#include <string.h>
#include <math.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
// visa.h is installed with the visa library that this code links with
#include "visa.h"
// This header is also in visa dir:
#include "PM100D_Drv.h"
extern ViStatus _VI_FUNC PM100D_measTemp (ViSession instr, ViPReal64 pVal);

typedef void op_func_t(int nlhs, mxArray *plhs[],
		       int nrhs, const mxArray *prhs[]);

op_func_t op_inq, op_open, op_close, op_meas_pwr_dBm, op_meas_temp, op_set_wavelen_nm, op_get_idn; 

op_func_t *ops[] = {
  /* 0 */   op_inq,  // err=pm100d_mex(0); // returns 0=ok,1=err
  /* 1 */   op_open, // err=pm100d_mex(1); // returns 0=ok,1=err
  /* 2 */   op_close, // pm100d_mex(2);     // closes meter
  /* 3 */   op_meas_pwr_dBm, // dbm=pm100d_mex(3); // returns dBm value
  /* 4 */   op_meas_temp, //temp_C=pm100d_mex(4); // returns dBm value
  /* 5 */   op_set_wavelen_nm, //wl_nm=pm100d_mex(5); // returns nm value of actual set
  /* 6 */   op_get_model_sn
};
#define OP_NUM (sizeof(ops)/sizeof(op_func_t *))






#define printf mexPrintf
#define TIMEOUT_MILLISEC   5000  // Communication timeout [ms]



#ifndef __TIMESTAMP__
#define __TIMESTAMP__ "?"
#endif


void error_msg(ViSession instrHdl, ViStatus err) {
  ViChar buf[PM100D_ERR_DESCR_BUFFER_SIZE];
  char str[80];
  PM100D_errorMessage (instrHdl, err, buf);
  sprintf(str, "pm100d_mex ERR: %s\n", buf);
  printf(str);
}


#define COMM_TIMEOUT 3000
ViStatus find_instruments(ViString findPattern, ViChar **resource, ViChar **idn) {
  ViStatus       err, rval;
  ViSession      resMgr, instr;
  ViFindList     findList;
  ViUInt32       findCnt;
  ViChar         instrDesc[256];
  static ViChar  returnStr[VI_FIND_BUFLEN], idnbuf[VI_FIND_BUFLEN];
  ViChar         name[256], sernr[256];
  int i;
                      
  if((err = viOpenDefaultRM(&resMgr))) return(err);
  switch((err = viFindRsrc(resMgr, findPattern, &findList, &findCnt, instrDesc))) {
    case VI_SUCCESS:
      break;
    case VI_ERROR_RSRC_NFOUND:
      printf("pm100d_mex: No matching instruments\n"); // fall thru
    default:
      viClose(findList);
      viClose(resMgr);
      return (err);
  }
  rval = VI_ERROR_RSRC_NFOUND;
  printf("Found %d matching instruments:\n\n", findCnt);
  for(i=1;1;++i) {
    printf("%d: %s ", i, instrDesc);
    if((err = viOpen (resMgr, instrDesc, VI_NULL, COMM_TIMEOUT, &instr)) != 0) {
      printf("ERR: cant open\n");
    }else {
      rval = VI_SUCCESS;
      strcpy(returnStr, instrDesc);
      *resource = returnStr;
      viGetAttribute(instr, VI_ATTR_MODEL_NAME,      name);
      viGetAttribute(instr, VI_ATTR_USB_SERIAL_NUM,  sernr);
      strcpy(idnbuf, name);
      strcat(idnbuf, ":");
      strcat(idnbuf, sernr);
      *idn = idnbuf;
      viClose(instr);
      printf("%s \tS/N:%s\n", name, sernr);
    }
    if (err = viFindNext(findList, instrDesc)) break;
  }
  viClose(findList);
  viClose(resMgr);
  return rval;
}








ViStatus get_pwr_dBm(ViSession ihdl, double *pwr_dBm) {
// pwr_dBm: on error, gets -1000.
  ViStatus err = VI_SUCCESS; 
  ViReal64 power=-1000.0;
  err = PM100D_setPowerUnit(ihdl, PM100D_POWER_UNIT_DBM);
  if (!err) { 
    err = PM100D_measPower(ihdl, &power);
    // can return VI_ERROR_INV_RESPONSE, meanin didnt parse rsp
    if ((err==VI_INSTR_WARN_NAN)||(err==VI_INSTR_WARN_UNDERRUN)) {
      power=-1000.0;
      err=0;
    } else if (err==VI_INSTR_WARN_OVERFLOW) {
      power=1000.0;
      err=0;
    }
  }
  *pwr_dBm = power;
  return err;
}


ViStatus drv_query_measure(ViSession instr, void *data, ViPReal64 ptr, ViString cmd, ...);

ViStatus get_temp(ViSession ihdl, double *temp_C_p) {
   ViStatus       err = VI_SUCCESS; 
   //   ViReal64       power;
   //   ViChar _VI_FAR name[256];
   //   ViChar _VI_FAR snr[256];
   //   ViChar _VI_FAR message[1024];
   ViInt16 typ, styp; // , flags;
   ViReal64 val;

   // Dan did issue this, and it is the case our "sensor" has a temp sensor.
   //   err = PM100D_getSensorInfo(ihdl, name, snr, message, &typ, &styp, &flags);
   //   printf("sensor name = %s\n", name);
   
   // PM100D_Drv.c does not provide a temperature measurement function.
   //  err = drv_query_measure(ihdl, VI_NULL, &val, "MEAS:SCAL:TEMP?\n");
   err = PM100D_measTemp(ihdl, &val);
   if (!err) {
     *temp_C_p = val;
   }
   return (err);
}


ViSession   instrHdl = VI_NULL;

ViChar      *rscName=0;
ViChar      *idn=0;

void op_inq(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  ViStatus    err;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if(instrHdl != VI_NULL)
    PM100D_close(instrHdl);
  err = find_instruments(PM100D_FIND_PATTERN, &rscName, &idn);
  if (err)
    mexPrintf("ERR: could not find any instruments\n");
  // if(err) error_msg(instrHdl, err);
  plhs[0] = mxCreateDoubleScalar(err!=VI_SUCCESS);
}

void op_open(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  ViStatus err=VI_SUCCESS;
  // printf("DBG: op_open\n");
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [err]");
  if(instrHdl != VI_NULL)
    PM100D_close(instrHdl);
  if (!rscName)
    err = find_instruments(PM100D_FIND_PATTERN, &rscName, &idn);
  if (rscName) {
    // printf("DBG: do init\n");
    err = PM100D_init(rscName, VI_OFF, VI_ON, &instrHdl);
    //printf("DBG: done init, err=%d\n", err);
    if (!err)
      viSetAttribute(instrHdl, VI_ATTR_TMO_VALUE, TIMEOUT_MILLISEC);
  }
  if (err)
    error_msg(instrHdl, err);
  plhs[0] = mxCreateDoubleScalar(err!=VI_SUCCESS);
}

void op_meas_pwr_dBm(int nlhs, mxArray *plhs[],
    	             int nrhs, const mxArray *prhs[]) {
  ViStatus err;
  double pwr_dBm;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [pwr_dbm]");
  if((err = get_pwr_dBm(instrHdl, &pwr_dBm)))
    error_msg(instrHdl, err);
  plhs[0] = mxCreateDoubleScalar(pwr_dBm);
}

void op_meas_temp(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  ViStatus    err;
  double temp_C=0;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [temp_C]");
  if((err = get_temp(instrHdl, &temp_C))) {
    error_msg(instrHdl, err);
    temp_C = 0;
  }
  plhs[0] = mxCreateDoubleScalar(temp_C);
}

void op_get_model_sn(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  mxArray *s;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is str");
  s = mxCreateString(idn);
  if (!s) mexErrMsgTxt("mxCreateString out of mem");
  plhs[0] = s;
}

void op_set_wavelen_nm(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  ViStatus    err;
  double wavelen_nm;
  if (nlhs!=1)
    mexErrMsgTxt("output arg is [wavelen_nm]");
  if (nrhs<2)
    mexErrMsgTxt("missing params");
  if (!mxIsDouble(prhs[1]))
    mexErrMsgTxt("second param (wavelen_nm) must be a double");
  wavelen_nm = *mxGetPr(prhs[1]);

  if (wavelen_nm>0) {
    err = PM100D_setWavelength(instrHdl, wavelen_nm); // tempViReal64 val)
    if (err) error_msg(instrHdl, err);
  }
  err = PM100D_getWavelength(instrHdl, PM100D_ATTR_SET_VAL, &wavelen_nm); // tempViReal64 val)
  if (err)  error_msg(instrHdl, err);
  plhs[0] = mxCreateDoubleScalar(wavelen_nm);
}


void op_close(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {
  if(instrHdl != VI_NULL)
    PM100D_close(instrHdl);
  instrHdl = VI_NULL;
}


void mexFunction(int nlhs, mxArray *plhs[],
		 int nrhs, const mxArray *prhs[]) {
  int op;
  double wavelen_nm;
  if (nrhs<1)
    mexErrMsgTxt("missing params");
  if (!mxIsDouble(prhs[0]))
    mexErrMsgTxt("operation must be a number");
  op = (int)*mxGetPr(prhs[0]);
  // mexPrintf("op %d\n", OP_NUM);
  if ((op<0)||(op>=OP_NUM)) {
    char msg[80];
    sprintf(msg, "bad operation %d\n", op);
    mexErrMsgTxt(msg);
  }
  // mexPrintf("op %d\n", op);
  ops[op](nlhs, plhs, nrhs, prhs);
}
