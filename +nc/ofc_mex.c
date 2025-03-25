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

op_func_t op_init, op_open,
  op_close;

op_func_t *ops[] = {
  /* 0 */   op_init,
  /* 1 */   op_open,
  /* 2 */   op_close,
}

  
#define OP_NUM (sizeof(ops)/sizeof(op_func_t *))


void op_init(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {

}
void op_open(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {

}
void op_close(int nlhs, mxArray *plhs[],
	     int nrhs, const mxArray *prhs[]) {

}
  
