/****************************************************************************

   Thorlabs PM100x Series VISA instrument driver

   This driver supports PM100A, PM100D and PM100USB optical power meters
   
   FOR DETAILED DESCRIPTION OF THE DRIVER FUNCTIONS SEE THE ONLINE HELP FILE
   AND THE PROGRAMMERS REFERENCE MANUAL.

   Copyright:  Copyright(c) 2008, 2009, Thorlabs (www.thorlabs.com)
   Author:     Michael Biebl (mbiebl@thorlabs.com),
               Diethelm Krause (dkrause@thorlabs.com),
               Thomas Schlosser (tschlosser@thorlabs.com)

   Disclaimer:

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


   Source file

   Date:          Nov-18-2009
   Built with:    NI LabWindows/CVI 9.0.1
   Software-Nr:   09.180.xxx
   Version:       2.0.0

   Changelog:     see 'readme.rtf'

****************************************************************************/


#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
//#include <utility.h>
#include <ctype.h>
#include <visa.h>
#include "PM100D_Drv.h"

/*===========================================================================
 Macros
===========================================================================*/
// Resource locking
#ifdef _CVI_DEBUG_
   // We are in a debugging session - do not lock resource
   #define LOCK_STATE            VI_NULL
#else
   //#define LOCK_STATE          VI_EXCLUSIVE_LOCK
   #define LOCK_STATE            VI_NULL
#endif

// Version
#define DRIVER_REVISION_TXT      "2.0.0"    // Instrument driver revision
#define UNKNOWN_REVISION_TXT     "unknown"

// Range checking
#define INVAL_RANGE(val, min, max)  ( ((val) < (min)) || ((val) > (max)) )

// buffer sizes
#define DRV_BUF_SIZE             (PM100D_BUFFER_SIZE)


/*===========================================================================
 Structures
===========================================================================*/
// static error list
typedef struct
{
   ViStatus err;
   ViString descr;
} errDescrStat_t;


// dynamic error list
typedef struct errDescrDyn_t  errDescrDyn_t;
typedef struct errDescrDyn_t
{
   ViStatus       err;
   ViChar         descr[DRV_BUF_SIZE];
   errDescrDyn_t  *next;
}  errDescrDyn_t;


// driver private data
typedef struct
{
   ViSession      instr;      // instrument handle
   ViBoolean      errQuery;   // auto error query
   errDescrDyn_t  *errList;   // dynamic error list
} drvData_t;


// character program data generation / character response interpreting (must be terminated with {0, NULL}
typedef struct
{
   ViInt16  val;
   ViChar   *str;
} valStr_t;



/*===========================================================================
 Constants
===========================================================================*/
/*---------------------------------------------------------------------------
 Static error descriptions
---------------------------------------------------------------------------*/
static const errDescrStat_t errDescrStat[] =
{
   {VI_ERROR_PARAMETER1,      "Parameter 1 out of range"                         },
   {VI_ERROR_PARAMETER2,      "Parameter 2 out of range"                         },
   {VI_ERROR_PARAMETER3,      "Parameter 3 out of range"                         },
   {VI_ERROR_PARAMETER4,      "Parameter 4 out of range"                         },
   {VI_ERROR_PARAMETER5,      "Parameter 5 out of range"                         },
   {VI_ERROR_PARAMETER6,      "Parameter 6 out of range"                         },
   {VI_ERROR_PARAMETER7,      "Parameter 7 out of range"                         },
   {VI_ERROR_PARAMETER8,      "Parameter 8 out of range"                         },
   {VI_ERROR_INV_RESPONSE,    "Errors occured interpreting instrument's response"},
   {VI_INSTR_WARN_OVERFLOW,   "WARNING: Value overflow"                          },
   {VI_INSTR_WARN_UNDERRUN,   "WARNING: Value underrun"                          },
   {VI_INSTR_WARN_NAN,        "WARNING: Value is NaN"                            },
   {0 , VI_NULL}  // termination

};

static const valStr_t   valStr_valAttrSetMinMaxDef[]  =
{
   {PM100D_ATTR_SET_VAL,  "" },
   {PM100D_ATTR_MIN_VAL,  "MIN" },
   {PM100D_ATTR_MAX_VAL,  "MAX" },
   {PM100D_ATTR_DFLT_VAL, "DEF" },
   {0,                     NULL  }
};

static const valStr_t   valStr_valAttrSetMinMax[]  =
{
   {PM100D_ATTR_SET_VAL,  "" },
   {PM100D_ATTR_MIN_VAL,  "MIN" },
   {PM100D_ATTR_MAX_VAL,  "MAX" },
   {0,                     NULL  }
};

static const valStr_t   valStr_powerUnit[] =
{
   {PM100D_POWER_UNIT_WATT,  "W" },
   {PM100D_POWER_UNIT_DBM,   "DBM"  },
   {0,                        NULL  }
};

static const valStr_t   valStr_sensType[] =
{
   {SENSOR_TYPE_PD_SINGLE,  "PHOT" },
   {SENSOR_TYPE_THERMO,     "THER" },
   {SENSOR_TYPE_PYRO,       "PYR"  },
   {0,                      NULL   }
};


/*===========================================================================
 Prototypes
===========================================================================*/
// Closing
static ViStatus drv_initClose (ViPSession instr, ViStatus stat);

// Dynamic error list functions
static ViString      drv_splitErrMsg(ViString str);
static void          drv_dynErrlist_free(errDescrDyn_t *list);
static ViStatus      drv_dynErrlist_lookup(errDescrDyn_t *list, ViStatus err, ViChar** descr);
static errDescrDyn_t *drv_dynErrlist_add(errDescrDyn_t *list, ViStatus err, ViChar* descr);

// I/O Communication
static ViStatus drv_write  (ViSession instr, drvData_t *data, ViString fmt, ...);
static ViStatus drv_read   (ViSession instr, drvData_t *data, ViChar *buf, ViUInt32 len, ViPUInt32 cnt);

// Query routines
static ViStatus drv_query_boolean   (ViSession instr, drvData_t *data, ViPBoolean ptr, ViString cmd, ...);
static ViStatus drv_query_int16     (ViSession instr, drvData_t *data, ViPInt16 ptr, ViString cmd, ...);
static ViStatus drv_query_3int16    (ViSession instr, drvData_t *data, ViPInt16 ptr1, ViPInt16 ptr2, ViPInt16 ptr3, ViString cmd, ...);
static ViStatus drv_query_double    (ViSession instr, drvData_t *data, ViPReal64 ptr, ViString cmd, ...);

//
// 10/27/17 Dan removed the static qualifier so this can be called
// from mex code:
ViStatus drv_query_measure   (ViSession instr, drvData_t *data, ViPReal64 ptr, ViString cmd, ...);

static ViStatus drv_query_charData  (ViSession instr, drvData_t *data, const valStr_t _VI_FAR *list, ViPInt16 ptr, ViString cmd, ...);
static ViStatus drv_query_sensinfo  (ViSession instr, drvData_t *data,  ViChar _VI_FAR name[], ViChar _VI_FAR snr[],  ViChar _VI_FAR message[], ViPInt16 pType, ViPInt16 pStype, ViPInt16 pFlags, ViString cmd, ...);

// Error checking
static ViStatus drv_checkInstrError(ViSession instr, drvData_t *data, ViPInt32 instrErr, ViPChar instrMsg);

// Parsing/Command generation
static ViStatus drv_interpretCharResponse(const valStr_t _VI_FAR *list, ViString rsp, ViPInt16 pVal);
static ViString drv_getStrFromVal(const valStr_t _VI_FAR *list, ViInt16 val);
static ViStatus digIoBits(ViInt16 val, ViPBoolean IO1, ViPBoolean IO2, ViPBoolean IO3, ViPBoolean IO4);
static ViStatus digIoValue(ViBoolean IO1, ViBoolean IO2, ViBoolean IO3, ViBoolean IO4, ViPInt16 val);

// String manipulation
static char    *unquoteString(char *str, char quote);
static size_t  quoteString(char *dst, const char *src);

// Numeric value qualification
static ViReal64 convertInfinity(ViReal64 val);
static ViStatus checkInfinity(ViReal64 val);


/*===========================================================================

 USER-CALLABLE FUNCTIONS (Exportable Functions)

===========================================================================*/
/*---------------------------------------------------------------------------
 Initialize - This function initializes the instrument driver session and
 returns an instrument handle which is used in subsequent calls.
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_init (ViRsrc rsc, ViBoolean IDQuery, ViBoolean reset, ViPSession pInstr)
{
   ViStatus    err;
   ViSession   rm = VI_NULL;
   ViUInt16    vid, pid, intf;
   drvData_t   *data;

   //Open instrument session and set 'user data' to 'VI_NULL'
   *pInstr = VI_NULL;
   if((err = viOpenDefaultRM(&rm))) return (err);
   if((err = viOpen(rm, rsc, LOCK_STATE, VI_NULL, pInstr)))
   {
      viClose(rm);
      return (err);
   }
   if((err = viSetAttribute(*pInstr, VI_ATTR_USER_DATA, (ViAttrState)VI_NULL)))
   {
      viClose(*pInstr);
      viClose(rm);
      return (err);
   }

   if((err = viGetAttribute (*pInstr, VI_ATTR_INTF_TYPE, &intf))) return (drv_initClose(pInstr, err));
   switch(intf)
   {
      case VI_INTF_USB:
         break;
      default:
         return (drv_initClose(pInstr, VI_ERROR_PARAMETER1));
   }

   if(IDQuery)
   {
      // Is it a Thorlabs PM100D
      if((err = viGetAttribute(*pInstr, VI_ATTR_MANF_ID,    &vid)))  return (drv_initClose(pInstr, err));
      if((err = viGetAttribute(*pInstr, VI_ATTR_MODEL_CODE, &pid)))  return (drv_initClose(pInstr, err));
      if(vid != PM100D_VID_THORLABS)                                        return (drv_initClose(pInstr, VI_ERROR_FAIL_ID_QUERY));
      switch(pid)
      {
         case PM100D_PID_PM100D:
         case PM100D_PID_PM100D_DFU:
         case PM100D_PID_PM100A:
         case PM100D_PID_PM100A_DFU:
         case PM100D_PID_PM100USB:
            break;
         default:
            return (drv_initClose(pInstr, VI_ERROR_FAIL_ID_QUERY));
      }
   }

   // Communication buffers
   if((err = viFlush (*pInstr, VI_WRITE_BUF_DISCARD | VI_READ_BUF_DISCARD)))  return (drv_initClose(pInstr, err));

   // Configure Session
   if ((err = viSetAttribute(*pInstr, VI_ATTR_TERMCHAR,     '\n')))           return (drv_initClose(pInstr, err));  // Set '\n' to termination character
   if ((err = viSetAttribute(*pInstr, VI_ATTR_SEND_END_EN,  VI_TRUE)))        return (drv_initClose(pInstr, err));  // Send 'EOM' bit on 'ViWrite()'
   if ((err = viSetAttribute(*pInstr, VI_ATTR_TERMCHAR_EN,  VI_FALSE)))       return (drv_initClose(pInstr, err));
   if ((err = viSetAttribute(*pInstr, VI_ATTR_IO_PROT,      VI_PROT_NORMAL))) return (drv_initClose(pInstr, err));  // Use USBTMC-USB488 protocol

   // Private driver data
   if((data = (drvData_t*)malloc(sizeof(drvData_t))) == NULL)                 return (drv_initClose(pInstr, VI_ERROR_SYSTEM_ERROR));
   if((err = viSetAttribute(*pInstr, VI_ATTR_USER_DATA, (ViAttrState)data)))  return (drv_initClose(pInstr, err));
   data->instr    = *pInstr;
   data->errList  = (errDescrDyn_t*)VI_NULL;
   data->errQuery = VI_ON;

   // Reset device status structure
   if((err = drv_write(*pInstr, data, "*CLS;*SRE 0;*ESE 0;:STAT:PRES\n")))    return (drv_initClose(pInstr, err));

   // Reset device
   if(reset)
   {
      if((err = drv_write(*pInstr, data, "*RST\n"))) return (drv_initClose(pInstr, err));
   }

   //Ready
   return (VI_SUCCESS);
}


/*---------------------------------------------------------------------------
 Close an instrument driver session
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_close (ViSession instr)
{
   return (drv_initClose(&instr, VI_SUCCESS));
}


/*===========================================================================

 Class: Configuration Functions.

===========================================================================*/
/*===========================================================================
 Subclass: Configuration Functions - System
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get date and time
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setTime (ViSession instr, ViInt16  year, ViInt16  month, ViInt16  day, ViInt16  hour, ViInt16  minute, ViInt16  second)
{
   ViStatus    err, warn = VI_SUCCESS;
   drvData_t   *data;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((err = (drv_write(instr, data, "SYST:DATE %d, %d, %d\n", year, month, day)) < 0)) return err;
   if(!warn) warn = err;   
   if((err = (drv_write(instr, data, "SYST:TIME %d, %d, %d\n", hour, minute, second)) < 0)) return err;
   if(!warn) warn = err;
   return (warn);
}

ViStatus _VI_FUNC PM100D_getTime (ViSession instr, ViPInt16 year, ViPInt16 month, ViPInt16 day, ViPInt16 hour, ViPInt16 minute, ViPInt16 second)
{
   ViStatus    err, warn = VI_SUCCESS;
   drvData_t   *data;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   
   if(year || month || day)
   {
      if((err = drv_query_3int16(instr, data, year, month, day, "SYST:DATE?\n")) < 0) return (err);
      if(!warn) warn = err;
   }
   
   if(hour || minute || second)
   {
      if((err = drv_query_3int16(instr, data, hour,  minute, second, "SYST:TIME?\n")) < 0) return (err);
      if(!warn) warn = err;
   }

   return (warn);
}

/*---------------------------------------------------------------------------
 Set/get line frequency
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setLineFrequency (ViSession instr, ViInt16 val)
{
   return (drv_write(instr, VI_NULL, "SYST:LFR %d\n", val));   
}

ViStatus _VI_FUNC PM100D_getLineFrequency (ViSession instr, ViPInt16 pVal)
{
   return (drv_query_int16(instr, VI_NULL, pVal, "SYST:LFR?\n"));    
}


/*===========================================================================
 Subclass: Configuration Functions - System -Instrument Registers
===========================================================================*/
/*---------------------------------------------------------------------------
 Write/read register contents
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_writeRegister (ViSession instr, ViInt16 reg, ViInt16 value)
{
   const valStr_t cmdStr[] =
   {
      {PM100D_REG_SRE,          "*SRE"           },
      {PM100D_REG_ESE,          "*ESE"           },
      {PM100D_REG_OPER_ENAB,    "STAT:OPER:ENAB" },
      {PM100D_REG_OPER_PTR,     "STAT:OPER:PTR"  },
      {PM100D_REG_OPER_NTR,     "STAT:OPER:NTR"  },
      {PM100D_REG_QUES_ENAB,    "STAT:QUES:ENAB" },
      {PM100D_REG_QUES_PTR,     "STAT:QUES:PTR"  },
      {PM100D_REG_QUES_NTR,     "STAT:QUES:NTR"  },
      {PM100D_REG_MEAS_ENAB,    "STAT:MEAS:ENAB" },
      {PM100D_REG_MEAS_PTR,     "STAT:MEAS:PTR"  },
      {PM100D_REG_MEAS_NTR,     "STAT:MEAS:NTR"  },
      {PM100D_REG_AUX_ENAB,     "STAT:AUX:ENAB"  },
      {PM100D_REG_AUX_PTR,      "STAT:AUX:PTR"   },
      {PM100D_REG_AUX_NTR,      "STAT:AUX:NTR"   },
      {0,                        NULL            }
   };

   ViChar *str;

   if((str = drv_getStrFromVal(cmdStr, reg)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   return (drv_write(instr, VI_NULL, "%s %d\n", str, value));
}

ViStatus _VI_FUNC PM100D_readRegister (ViSession instr, ViInt16 reg, ViPInt16 value)
{
   const valStr_t cmdStr[] =
   {
      {PM100D_REG_STB,          "*STB?\n"           },
      {PM100D_REG_SRE,          "*SRE?\n"           },
      {PM100D_REG_ESB,          "*ESR?\n"           },
      {PM100D_REG_ESE,          "*ESE?\n"           },
      {PM100D_REG_OPER_COND,    "STAT:OPER:COND?\n" },
      {PM100D_REG_OPER_EVENT,   "STAT:OPER?\n"      },
      {PM100D_REG_OPER_ENAB,    "STAT:OPER:ENAB?\n" },
      {PM100D_REG_OPER_PTR,     "STAT:OPER:PTR?\n"  },
      {PM100D_REG_OPER_NTR,     "STAT:OPER:NTR?\n"  },
      {PM100D_REG_QUES_COND,    "STAT:QUES:COND?\n" },
      {PM100D_REG_QUES_EVENT,   "STAT:QUES?\n"      },
      {PM100D_REG_QUES_ENAB,    "STAT:QUES:ENAB?\n" },
      {PM100D_REG_QUES_PTR,     "STAT:QUES:PTR?\n"  },
      {PM100D_REG_QUES_NTR,     "STAT:QUES:NTR?\n"  },
      {PM100D_REG_MEAS_COND,    "STAT:MEAS:COND?\n" },
      {PM100D_REG_MEAS_EVENT,   "STAT:MEAS?\n"      },
      {PM100D_REG_MEAS_ENAB,    "STAT:MEAS:ENAB?\n" },
      {PM100D_REG_MEAS_PTR,     "STAT:MEAS:PTR?\n"  },
      {PM100D_REG_MEAS_NTR,     "STAT:MEAS:NTR?\n"  },
      {PM100D_REG_AUX_COND,     "STAT:AUX:COND?\n"  },
      {PM100D_REG_AUX_EVENT,    "STAT:AUX?\n"       },
      {PM100D_REG_AUX_ENAB,     "STAT:AUX:ENAB?\n"  },
      {PM100D_REG_AUX_PTR,      "STAT:AUX:PTR?\n"   },
      {PM100D_REG_AUX_NTR,      "STAT:AUX:NTR?\n"   },
      {0,                        NULL               }
   };

   ViChar *str;

   if((str = drv_getStrFromVal(cmdStr, reg)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   return (drv_query_int16(instr, VI_NULL, value, str));
}


/*===========================================================================
 Subclass: Configuration Functions - Display
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get display brightness
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setDispBrightness (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "DISP:BRIG %f\n", val));
}

ViStatus _VI_FUNC PM100D_getDispBrightness (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_double(instr, VI_NULL, pVal, "DISP:BRIG?\n"));
}

/*---------------------------------------------------------------------------
 Set/get display contrast
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setDispContrast (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "DISP:CONT %f\n", val));
}

ViStatus _VI_FUNC PM100D_getDispContrast (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_double(instr, VI_NULL, pVal, "DISP:CONT?\n"));
}

/*===========================================================================
 Subclass: Configuration Functions - Calibration message
===========================================================================*/
/*---------------------------------------------------------------------------
 Read calibration message
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_getCalibrationMsg (ViSession instr, ViChar _VI_FAR str[])
{
   ViStatus err;
   ViChar   rsp[PM100D_BUFFER_SIZE];
   ViUInt32 len;

   if((err = viWrite (instr, "CAL:STR?\n", 10, VI_NULL)) < 0) return (err);
   if((err = drv_read(instr, VI_NULL, rsp, sizeof(rsp), VI_NULL))) return (err);
   if(sscanf(rsp, " \"%[^\n]", str) < 1)  return (VI_ERROR_INV_RESPONSE);
   // remove trailing "
   len = strlen(str);
   str[len -1] = '\0';
   unquoteString(str, '"');

   return (VI_SUCCESS);
}


/*===========================================================================
 Subclass: Configuration Functions - Sense - Average
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get average count
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setAvgCnt (ViSession instr, ViInt16 val)
{
   return (drv_write(instr, VI_NULL, "SENS:AVER:COUN %d\n", val));   
}

ViStatus _VI_FUNC PM100D_getAvgCnt (ViSession instr, ViPInt16 pVal)
{
   return (drv_query_int16(instr, VI_NULL, pVal, "SENS:AVER:COUN?\n")); 
}


/*===========================================================================
 Subclass: Configuration Functions - Sense - Correction
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get attenuation
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setAttenuation (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:LOSS:INP:MAGN %f\n", val));
}

ViStatus _VI_FUNC PM100D_getAttenuation (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:CORR:LOSS:INP:MAGN? %s\n", str));
}

/*---------------------------------------------------------------------------
 dark current adjustment
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_startDarkAdjust (ViSession instr)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:COLL:ZERO:INIT\n")); 
}

ViStatus _VI_FUNC PM100D_cancelDarkAdjust (ViSession instr)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:COLL:ZERO:ABORT\n"));   
}

ViStatus _VI_FUNC PM100D_getDarkAdjustState (ViSession instr, ViPInt16 pVal)
{
   return (drv_query_int16(instr, VI_NULL, pVal, "SENS:CORR:COLL:ZERO:STATE?\n"));  
}

ViStatus _VI_FUNC PM100D_getDarkOffset (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_double(instr, VI_NULL, pVal, "SENS:CORR:COLL:ZERO:MAGN?\n"));     
}

/*---------------------------------------------------------------------------
 Set/get beam diameter
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setBeamDia (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:BEAM %f\n", val));   
}

ViStatus _VI_FUNC PM100D_getBeamDia (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:CORR:BEAM? %s\n", str)); 
}

/*---------------------------------------------------------------------------
 Set/get wavelength
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setWavelength (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:WAV %f\n", val)); 
}

ViStatus _VI_FUNC PM100D_getWavelength (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:CORR:WAV? %s\n", str));  
}

/*---------------------------------------------------------------------------
 Set/get photodiode responsivity
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPhotodiodeResponsivity (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:POW:PDI:RESP %f\n", val)); 
}

ViStatus _VI_FUNC PM100D_getPhotodiodeResponsivity (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:CORR:POW:PDI:RESP? %s\n", str));  
}

/*---------------------------------------------------------------------------
 Set/get thermopile responsivity
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setThermopileResponsivity (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:POW:THER:RESP %f\n", val));   
}

ViStatus _VI_FUNC PM100D_getThermopileResponsivity (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:CORR:POW:THER:RESP? %s\n", str)); 
}

/*---------------------------------------------------------------------------
 Set/get pyrosensor responsivity
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPyrosensorResponsivity (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:CORR:ENER:PYRO:RESP %f\n", val));  
}

ViStatus _VI_FUNC PM100D_getPyrosensorResponsivity (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:CORR:ENER:PYRO:RESP? %s\n", str));   
}


/*===========================================================================
 Subclass: Configuration Functions - Sense - Energy
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get energy range
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setEnergyRange (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:ENER:RANG:UPP %f\n", val));  
}

ViStatus _VI_FUNC PM100D_getEnergyRange (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:ENER:RANG:UPP? %s\n", str));      
}

/*---------------------------------------------------------------------------
 Set/get energy reference value
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setEnergyRef (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:ENER:REF %f\n", val)); 
}

ViStatus _VI_FUNC PM100D_getEnergyRef (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, VI_NULL, pVal, "SENS:ENER:REF? %s\n", str));  
}

/*---------------------------------------------------------------------------
 Set/get energy reference state
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setEnergyRefState (ViSession instr, ViBoolean val)
{
   ViStatus    err;
   drvData_t   *data;

   switch(val)
   {
      case VI_OFF:
      case VI_ON:
         break;
      default:
         return (VI_ERROR_PARAMETER2);
   }
   return (drv_write(instr, VI_NULL, "SENS:ENER:REF:STAT %d\n", (ViInt32)val));
}

ViStatus _VI_FUNC PM100D_getEnergyRefState (ViSession instr, ViPBoolean pVal)
{
   return (drv_query_boolean(instr, VI_NULL, pVal, "SENS:ENER:REF:STAT?\n")); 
}

/*===========================================================================
 Subclass: Configuration Functions - Sense - Frequency
===========================================================================*/
/*---------------------------------------------------------------------------
 Get frequency range
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_getFreqRange (ViSession instr, ViPReal64 lowerFrequency, ViPReal64 upperFrequency)
{
   ViStatus    err, warn = VI_SUCCESS;
   drvData_t   *data;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);

   if(lowerFrequency)   
   {
      if((err = drv_query_double(instr, data, lowerFrequency, "SENS:FREQ:RANG:LOW?\n")) < 0) return (err);
      if(!warn) warn = err;
   }
   if(upperFrequency)
   {
      if((err = drv_query_double(instr, data, upperFrequency, "SENS:FREQ:RANG:UPP?\n")) < 0) return (err);
      if(!warn) warn = err;
   }

   return (warn); 
}


/*===========================================================================
 Subclass: Configuration Functions - Sense - Power
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get power range auto
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPowerAutoRange (ViSession instr, ViBoolean val)
{
   ViStatus    err;
   drvData_t   *data;  

   switch(val)
   {
      case VI_OFF:
      case VI_ON:
         break;
      default:
         return (VI_ERROR_PARAMETER2);
   }
   return (drv_write(instr, VI_NULL, "SENS:POW:RANG:AUTO %d\n", (ViInt32)val));  
}

ViStatus _VI_FUNC PM100D_getPowerAutorange (ViSession instr, ViPBoolean pVal)
{
   return (drv_query_boolean(instr, VI_NULL, pVal, "SENS:POW:RANG:AUTO?\n")); 
}

/*---------------------------------------------------------------------------
 Set/get power range
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPowerRange (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:POW:RANG:UPP %f\n", val));   
   
}

ViStatus _VI_FUNC PM100D_getPowerRange (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:POW:RANG:UPP? %s\n", str));    
}

/*---------------------------------------------------------------------------
 Set/get power reference value
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPowerRef (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:POW:REF %f\n", val));  
}

ViStatus _VI_FUNC PM100D_getPowerRef (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, VI_NULL, pVal, "SENS:POW:REF? %s\n", str));   
}

/*---------------------------------------------------------------------------
 Set/get power reference state
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPowerRefState (ViSession instr, ViBoolean val)
{
   ViStatus    err;
   drvData_t   *data;

   switch(val)
   {
      case VI_OFF:
      case VI_ON:
         break;
      default:
         return (VI_ERROR_PARAMETER2);
   }
   return (drv_write(instr, VI_NULL, "SENS:POW:REF:STAT %d\n", (ViInt32)val));   
}

ViStatus _VI_FUNC PM100D_getPowerRefState (ViSession instr, ViPBoolean pVal)
{
   return (drv_query_boolean(instr, VI_NULL, pVal, "SENS:POW:REF:STAT?\n"));  
}

/*---------------------------------------------------------------------------
 Set/get power unit
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPowerUnit (ViSession instr, ViInt16 val)
{
   ViChar *str;

   if((str = drv_getStrFromVal(valStr_powerUnit, val)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   return (drv_write(instr, VI_NULL, "SENS:POW:DC:UNIT %s\n", str)); 
}

ViStatus _VI_FUNC PM100D_getPowerUnit (ViSession instr, ViPInt16 pVal)
{
   return (drv_query_charData(instr, VI_NULL, valStr_powerUnit, pVal, "SENS:POW:DC:UNIT?\n"));
}

/*===========================================================================
 Subclass: Configuration Functions - Sense - Peak
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get peak threshold
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setPeakThreshold (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "SENS:PEAK:THR %f\n", val)); 
}

ViStatus _VI_FUNC PM100D_getPeakThreshold (ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "SENS:PEAK:THR? %s\n", str));  
}

/*===========================================================================
 Subclass: Configuration Functions - Input
===========================================================================*/
/*===========================================================================
 Subclass: Configuration Functions - Input - Photodiode
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get photodiode input filter state
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setInputFilterState (ViSession instr, ViBoolean val)
{
   ViStatus    err;
   drvData_t   *data;

   switch(val)
   {
      case VI_OFF:
      case VI_ON:
         break;
      default:
         return (VI_ERROR_PARAMETER2);
   }
   return (drv_write(instr, VI_NULL, "INP:PDI:FILT:LPAS:STAT %d\n", (ViInt32)val)); 
}

ViStatus _VI_FUNC PM100D_getInputFilterState (ViSession instr, ViPBoolean pVal)
{
   return (drv_query_boolean(instr, VI_NULL, pVal, "INP:PDI:FILT:LPAS:STAT?\n"));   
}

/*===========================================================================
 Subclass: Configuration Functions - Input - Thermopile
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get thermopile accelerator state
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setAccelState (ViSession instr, ViBoolean val)
{
   ViStatus    err;
   drvData_t   *data;

   switch(val)
   {
      case VI_OFF:
      case VI_ON:
         break;
      default:
         return (VI_ERROR_PARAMETER2);
   }
   return (drv_write(instr, VI_NULL, "INP:THER:ACC:STAT %d\n", (ViInt32)val));
}

ViStatus _VI_FUNC PM100D_getAccelState (ViSession instr, ViPBoolean pVal)
{
   return (drv_query_boolean(instr, VI_NULL, pVal, "INP:THER:ACC:STAT?\n"));  
}

/*---------------------------------------------------------------------------
 Set/get thermopile accelerator mode
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setAccelMode (ViSession instr, ViBoolean val)
{
   ViStatus    err;
   drvData_t   *data;

   switch(val)
   {
      case VI_OFF:
      case VI_ON:
         break;
      default:
         return (VI_ERROR_PARAMETER2);
   }
   return (drv_write(instr, VI_NULL, "INP:THER:ACC:AUTO %d\n", (ViInt32)val));
}

ViStatus _VI_FUNC PM100D_getAccelMode (ViSession instr, ViPBoolean pVal)
{
   return (drv_query_boolean(instr, VI_NULL, pVal, "INP:THER:ACC:AUTO?\n"));  
}

/*---------------------------------------------------------------------------
 Set/get thermopile acceleration tau (time constant)
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setAccelTau (ViSession instr, ViReal64 val)
{
   return (drv_write(instr, VI_NULL, "INP:THER:ACC:TAU %f\n", val)); 
}

ViStatus _VI_FUNC PM100D_getAccelTau(ViSession instr, ViInt16 attr, ViPReal64 pVal)
{
   ViStatus    err;
   drvData_t   *data;
   ViChar      *str;

   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   if((str = drv_getStrFromVal(valStr_valAttrSetMinMaxDef, attr)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   
   return (drv_query_double(instr, data, pVal, "INP:THER:ACC:TAU? %s\n", str));  
}


/*===========================================================================
 Subclass: Configuration Functions - Input - Custom Sensor
===========================================================================*/
/*---------------------------------------------------------------------------
 Set/get custom sensor input adapter type
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_setInputAdapterType (ViSession instr, ViInt16 val)
{
   ViChar *str;

   if((str = drv_getStrFromVal(valStr_sensType, val)) == VI_NULL) return (VI_ERROR_PARAMETER2);
   return (drv_write(instr, VI_NULL, "INP:ADAP:TYPE %s\n", str)); 
}

ViStatus _VI_FUNC PM100D_getInputAdapterType (ViSession instr, ViPInt16 pVal)
{
   return (drv_query_charData(instr, VI_NULL, valStr_sensType, pVal, "INP:ADAP:TYPE?\n"));
}


/*===========================================================================

 Data Functions.

===========================================================================*/

ViStatus _VI_FUNC PM100D_measPower (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_measure(instr, VI_NULL, pVal, "MEAS:SCAL:POW?\n"));
}
// DAN ADDED THIS ONE:
ViStatus _VI_FUNC PM100D_measTemp (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_measure(instr, VI_NULL, pVal, "MEAS:SCAL:TEMP?\n"));
}

ViStatus _VI_FUNC PM100D_measEnergy (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_measure(instr, VI_NULL, pVal, "MEAS:SCAL:ENER?\n"));
}

ViStatus _VI_FUNC PM100D_measFreq (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_measure(instr, VI_NULL, pVal, "MEAS:SCAL:FREQ?\n"));  
}

ViStatus _VI_FUNC PM100D_measPowerDens (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_measure(instr, VI_NULL, pVal, "MEAS:SCAL:PDEN?\n"));  
}

ViStatus _VI_FUNC PM100D_measEnergyDens (ViSession instr, ViPReal64 pVal)
{
   return (drv_query_measure(instr, VI_NULL, pVal, "MEAS:SCAL:EDEN?\n"));  
}


/*===========================================================================

 Sensor Information.

 ===========================================================================*/

/*---------------------------------------------------------------------------
 Get sensor information
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_getSensorInfo (ViSession instr, ViChar _VI_FAR name[], ViChar _VI_FAR snr[], ViChar _VI_FAR message[], ViPInt16 pType, ViPInt16 pStype, ViPInt16 pFlags)
{
   return (drv_query_sensinfo(instr, VI_NULL, name, snr, message, pType, pStype, pFlags, "SYST:SENS:IDN?\n"));
}


/*===========================================================================

 Utility Functions.

 ===========================================================================*/
/*---------------------------------------------------------------------------
 Identification query
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_identificationQuery (ViSession instr, ViChar _VI_FAR vendor[], ViChar _VI_FAR name[], ViChar _VI_FAR serial[], ViChar _VI_FAR revision[])
{
   ViStatus err;
   ViChar   rsp[PM100D_BUFFER_SIZE];
   ViChar   vnd[PM100D_BUFFER_SIZE];
   ViChar   nam[PM100D_BUFFER_SIZE];
   ViChar   snr[PM100D_BUFFER_SIZE];
   ViChar   ver[PM100D_BUFFER_SIZE];

   if((err = viWrite (instr, "*IDN?\n", 6, VI_NULL)) < 0) return (err);
   if((err = drv_read(instr, VI_NULL, rsp, sizeof(rsp), VI_NULL))) return (err);
   if(sscanf(rsp, "%[^,], %[^,], %[^,], %[^\n]", vnd, nam, snr, ver) < 4)  return (VI_ERROR_INV_RESPONSE);

   if(vendor)     strcpy(vendor, vnd);
   if(name)       strcpy(name, nam);
   if(serial)     strcpy(serial, snr);
   if(revision)   strcpy(revision, ver);

   return (VI_SUCCESS);
}

/*---------------------------------------------------------------------------
 Reset the instrument.
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_reset (ViSession instr)
{
   return (drv_write(instr, VI_NULL, "*RST\n"));
}

/*---------------------------------------------------------------------------
 Run Self-Test routine.
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_selfTest (ViSession instr, ViPInt16 pVal)
{
   ViStatus       err;
   drvData_t *data;
   size_t         len;
   char           buf[PM100D_BUFFER_SIZE];

   if((err = viWrite (instr, "*TST?\n", 6, VI_NULL)) < 0)   return (err);
   if((err = viRead(instr, buf, sizeof(buf), VI_NULL)) < 0) return (err);
   sscanf(buf, " %hd \n ", pVal);
   return(drv_checkInstrError(instr, VI_NULL, VI_NULL, VI_NULL));
}

/*---------------------------------------------------------------------------
 Switch error query mode
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_errorQueryMode (ViSession instr, ViBoolean mode)
{
   ViStatus       err;
   drvData_t *data;

   switch(mode)
   {
      case VI_OFF:
      case VI_ON:
         break;

      default:
         return (VI_ERROR_PARAMETER2);
   }
   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   data->errQuery = mode;
   return (VI_SUCCESS);
}

/*---------------------------------------------------------------------------
 Error Query
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_errorQuery (ViSession instr, ViPInt32 pNum, ViChar _VI_FAR msg[])
{
   return (drv_checkInstrError(instr, VI_NULL, pNum, msg));
}

/*---------------------------------------------------------------------------
 Get error message. This function translates the error return value from the
 instrument driver into a user-readable string.
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_errorMessage(ViSession instr, ViStatus stat, ViChar _VI_FAR msg[])
{
   ViStatus             err;
   ViChar               *str;
   drvData_t            *data;
   const errDescrStat_t *ptr;

   // VISA errors
   if(viStatusDesc(instr, stat, msg) != VI_WARN_UNKNOWN_STATUS) return (VI_SUCCESS);

   // Static driver errors
   ptr = errDescrStat;
   while(ptr->descr != VI_NULL)
   {
      if(ptr->err == stat)
      {
         strcpy(msg, ptr->descr);
         return (VI_SUCCESS);
      }
      ptr ++;
   }

   // Dynamic instrument errors
   if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data)) != VI_SUCCESS) return (err);
   if((err = drv_dynErrlist_lookup(data->errList, stat, &str)) == VI_SUCCESS)
   {
      strcpy(msg, str);
      return VI_SUCCESS;
   }

   // Not found
   viStatusDesc(instr, VI_WARN_UNKNOWN_STATUS, msg);
   return (VI_WARN_UNKNOWN_STATUS);
}

/*---------------------------------------------------------------------------
 Revision Query
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_revisionQuery (ViSession instr, ViChar _VI_FAR driverRev[], ViChar _VI_FAR instrRev[])
{
   // Driver revision
   if(driverRev) strcpy(driverRev, DRIVER_REVISION_TXT);

   // Firmware revision
   if(instrRev)
   {
      if(instr)
      {
         return (PM100D_identificationQuery(instr, VI_NULL, VI_NULL, VI_NULL, instrRev));
      }
      strcpy(instrRev, UNKNOWN_REVISION_TXT);
   }
   return (VI_SUCCESS);
}


/*===========================================================================
 Class: Utility-Raw I/O
===========================================================================*/
/*---------------------------------------------------------------------------
 Write to Instrument
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_writeRaw (ViSession instr, ViString command)
{
   ViStatus    err;

   if((err = viWrite (instr, command, strlen(command), VI_NULL)) < 0)   return (err);
   return (VI_SUCCESS);
}

/*---------------------------------------------------------------------------
 Read from Instrument
---------------------------------------------------------------------------*/
ViStatus _VI_FUNC PM100D_readRaw (ViSession instr, ViChar _VI_FAR buffer[], ViUInt32 size, ViPUInt32 returnCount)
{
   return (viRead(instr, buffer, size, returnCount));
}


/*===========================================================================

 UTILITY ROUTINES (Non-Exportable Functions)

===========================================================================*/
/*---------------------------------------------------------------------------
 Get string from value.
 Return value: pointer to string. 'VI_NULL' if not found
---------------------------------------------------------------------------*/
static ViString drv_getStrFromVal(const valStr_t _VI_FAR *list, ViInt16 val)
{
   // Find in list
   while(list->str)
   {
      if(val == list->val) return (list->str);
      list ++;
   }
   return (VI_NULL);
}

/*---------------------------------------------------------------------------
 Interpret character response message
---------------------------------------------------------------------------*/
static ViStatus drv_interpretCharResponse(const valStr_t _VI_FAR *list, ViString rsp, ViPInt16 pVal)
{
   ViChar *str;

   // Convert 'rsp' to uppercase
   str = rsp;
   while(*str)
   {
      *str = toupper(*str);
      str ++;
   }

   // Find in list
   while(list->str)
   {
      if(!strcmp(rsp, list->str))
      {
         *pVal = list->val;
         return (VI_SUCCESS);
      }
      list ++;
   }
   return (VI_ERROR_INV_RESPONSE);
}

/*===========================================================================
 I/O Functions
===========================================================================*/
static ViStatus drv_write(ViSession instr, drvData_t *data, ViString fmt, ...)
{
   ViStatus    err;
   va_list     arg_ptr;
   ViUInt32    len;
   ViChar      buf[DRV_BUF_SIZE];

   va_start (arg_ptr, fmt);
   len = vsprintf (buf, fmt, arg_ptr);
   va_end (arg_ptr);

   if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
   if(!data)
   {
      if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   }
   if(data->errQuery) return (drv_checkInstrError(instr, data, VI_NULL, VI_NULL));
   return (VI_SUCCESS);
}

static ViStatus drv_read(ViSession instr, drvData_t *data, ViChar *buf, ViUInt32 len, ViPUInt32 cnt)
{
   ViStatus    err;
   ViUInt32    retcnt;

   if(cnt) *cnt = 0;

   // Get private data
   if(!data)
   {
      if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   }

   if((err = viRead(instr, buf, len, &retcnt)) < 0)
   {
      // We have a read error
      buf[0] = '\0';
      if(cnt) *cnt = 0;
      switch(err)
      {
         case VI_ERROR_TMO:
            // Timeout. Probably the query was not allowed
            if(data->errQuery)
            {
               // Return instrument error if there was one
               if((err = drv_checkInstrError(instr, data, VI_NULL, VI_NULL))) return (err);
            }
            // Return timeout error
            return(err);

         default:
            return(err);
      }
   }

   if(data->errQuery)
   {
      if((err = drv_checkInstrError(instr, data, VI_NULL, VI_NULL))) return (err);
   }

   buf[retcnt] = '\0';
   if(cnt) *cnt = retcnt;
   return (VI_SUCCESS);
}

static ViStatus drv_query(ViSession instr, drvData_t *data, ViChar *wr_buf, ViUInt32 wr_len, ViChar *rd_buf, ViUInt32 rd_len, ViPUInt32 cnt)
{
   ViStatus err, err2;
   int      tmocnt = 2;

   do
   {
      if((err = viWrite (instr, wr_buf, wr_len, VI_NULL)) < 0) return (err);
      err = drv_read(instr, data, rd_buf, rd_len, cnt);
      if(err == VI_ERROR_TMO)
      {
         // Timeout. Probably the query can be restarted
         tmocnt--;
         Sleep(0.5);
         err2 = viClear(instr);
         if(err2 != VI_SUCCESS)
            err = err2;
      }
   } while((tmocnt) && (err == VI_ERROR_TMO));
   
   return (err);
}

static ViStatus drv_query_boolean(ViSession instr, drvData_t *data, ViPBoolean ptr, ViString cmd, ...)
{
   ViStatus err;
   va_list  arg_ptr;
   ViUInt32 len;
   ViUInt16 val;
   ViChar   buf[DRV_BUF_SIZE];

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, buf, sizeof(buf), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, buf, sizeof(buf), VI_NULL)) < 0)  return (err);
   if(sscanf(buf, " %hd \n ", &val) < 1) return (VI_ERROR_INV_RESPONSE);
   *ptr = val ? VI_ON : VI_OFF;
   return (VI_SUCCESS);
}

static ViStatus drv_query_int16(ViSession instr, drvData_t *data, ViPInt16 ptr, ViString cmd, ...)
{
   ViStatus err;
   va_list  arg_ptr;
   ViUInt32 len;
   ViChar   buf[DRV_BUF_SIZE];

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, buf, sizeof(buf), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, buf, sizeof(buf), VI_NULL)) < 0)  return (err);
   if(sscanf(buf, " %hd \n ", ptr) < 1) return (VI_ERROR_INV_RESPONSE);
   return (VI_SUCCESS);
}

static ViStatus drv_query_3int16(ViSession instr, drvData_t *data, ViPInt16 ptr1, ViPInt16 ptr2, ViPInt16 ptr3, ViString cmd, ...)
{
   ViStatus err;
   va_list  arg_ptr;
   ViUInt32 len;
   ViChar   buf[DRV_BUF_SIZE];

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, buf, sizeof(buf), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, buf, sizeof(buf), VI_NULL)) < 0)  return (err);
   if(sscanf(buf, " %hd, %hd, %hd \n ", ptr1, ptr2, ptr3) < 1) return (VI_ERROR_INV_RESPONSE);
   return (VI_SUCCESS);
}

static ViStatus drv_query_double(ViSession instr, drvData_t *data, ViPReal64 ptr, ViString cmd, ...)
{
   ViStatus err;
   va_list  arg_ptr;
   ViUInt32 len;
   ViChar   buf[DRV_BUF_SIZE];

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, buf, sizeof(buf), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, buf, sizeof(buf), VI_NULL)) < 0)  return (err);
   if(sscanf(buf, " %lf \n ", ptr) < 1) return (VI_ERROR_INV_RESPONSE);
   *ptr = convertInfinity(*ptr);
   return (checkInfinity(*ptr));
}

static ViStatus drv_query_measure(ViSession instr, drvData_t *data, ViPReal64 ptr, ViString cmd, ...)
{
   ViStatus err, err2;
   va_list  arg_ptr;
   ViUInt32 len;
   ViChar   buf[DRV_BUF_SIZE];
   
   ViChar msg[1000];

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, buf, sizeof(buf), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, buf, sizeof(buf), VI_NULL)) < 0) 
// {
//    if(err == VI_ERROR_TMO)
//    {
//       err2 = viClear(instr);
//       if(err2 == VI_SUCCESS)
//          return err;
//       else
//          return err2;
//       
//    }
// }
   if(sscanf(buf, " %lf \n ", ptr) < 1) return (VI_ERROR_INV_RESPONSE);
   *ptr = convertInfinity(*ptr);
   return (checkInfinity(*ptr));
}

static ViStatus drv_query_charData(ViSession instr, drvData_t *data, const valStr_t _VI_FAR *list, ViPInt16 ptr, ViString cmd, ...)
{
   ViStatus err;
   va_list  arg_ptr;
   ViUInt32 len;
   ViChar   buf[DRV_BUF_SIZE];
   ViChar   rsp[DRV_BUF_SIZE];

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, rsp, sizeof(rsp), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, rsp, sizeof(rsp), VI_NULL)) < 0)  return (err);
   if(sscanf(rsp, " %[^\n] ", buf) < 1) return (VI_ERROR_INV_RESPONSE);
   return(drv_interpretCharResponse(list, buf, ptr));
}

static ViStatus drv_query_sensinfo(ViSession instr, drvData_t *data,  ViChar _VI_FAR name[], ViChar _VI_FAR snr[],  ViChar _VI_FAR message[], ViPInt16 pType, ViPInt16 pStype, ViPInt16 pFlags, ViString cmd, ...)
{
   ViStatus err;
   va_list  arg_ptr;
   ViUInt32 len;
   ViChar   buf[DRV_BUF_SIZE], buf1[DRV_BUF_SIZE];
   ViInt16  i=0, j=0;

   va_start (arg_ptr, cmd);
   len = vsprintf (buf, cmd, arg_ptr);
   va_end (arg_ptr);

   if((err = drv_query(instr, data, buf, len, buf, sizeof(buf), VI_NULL)) < 0) return (err);
// if((err = viWrite (instr, buf, len, VI_NULL)) < 0) return (err);
// if((err = drv_read(instr, data, buf, sizeof(buf), VI_NULL)) < 0)  return (err);
   
   while(buf[i] != ',') // get name
   {
       name[j] = buf[i];
       i++;
       j++;
   }
   name[j] = 0; 
   i++; // step over next ','

   j = 0;   
   while(buf[i] != ',') // get serial number
   {
       snr[j] = buf[i];
       i++;
       j++;
   }
   snr[j] = 0; 
   i++; // step over next ','

   j = 0;
   while(buf[i] != ',') // get message
   {
       message[j] = buf[i];
       i++;
       j++;
   }
   message[j] = 0;
   i++; // step over next ','
   
   if(sscanf(&buf[i], " %hd, %hd, %hd \n ", pType, pStype, pFlags) < 1) return (VI_ERROR_INV_RESPONSE);
   return (VI_SUCCESS);
}

static ViStatus drv_checkInstrError(ViSession instr, drvData_t *data, ViPInt32 instrErr, ViPChar instrMsg)
{
   ViStatus    err, ret_err = VI_SUCCESS;
   ViUInt32    cnt;
   ViUInt32    loop = 0;
   ViChar      rsp[DRV_BUF_SIZE];
   ViInt32     val;
   ViChar      msg[DRV_BUF_SIZE];

   // Get private data
   if(data == VI_NULL)
   {
      if((err = viGetAttribute(instr, VI_ATTR_USER_DATA, &data))) return (err);
   }

   // Loop through all errors
   do
   {
      // Query the device
      if((err = viWrite (instr, "SYST:ERR?\n", 11, VI_NULL)) < 0)   return (err);
      if((err = viRead (instr, rsp, sizeof(rsp), &cnt)) < 0)         return (err);
      rsp[cnt] = '\0';
      if(sscanf(rsp, "%ld, \"%[^\"\n]", &val, msg) < 2)              return (VI_ERROR_INV_RESPONSE);

      // most recent error
      if(!loop)
      {
         // pass to user
         if(instrErr) *instrErr = val;
         if(instrMsg) strcpy(instrMsg, msg);
      }

      // add error to driver store
      if(val)
      {
         err = val + VI_INSTR_ERROR_OFFSET;
         // store return value
         if(ret_err == VI_SUCCESS) ret_err = err;
         drv_splitErrMsg(msg);
         // Add instrument error to dynamic error list
         data->errList = drv_dynErrlist_add(data->errList, err, msg);
      }

      loop ++;
   }
   while(val);

   return (ret_err);
}

/*===========================================================================
 Numeric value qualification
===========================================================================*/
/*-----------------------------------------------------------------------------
 Infinity helpers
-----------------------------------------------------------------------------*/
static ViReal64 bytesToViReal64(const ViUInt8 bytes[])
{
   union
   {
      ViUInt8  b[sizeof(ViReal64)];
      ViReal64 f;
   }  conv;
   memcpy(conv.b, bytes, sizeof(ViReal64));
   return (conv.f);
}

static ViReal64 posInfinity(void)
{
   static const ViUInt8 InfBytes[sizeof(ViReal64)] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x7F };
   return (bytesToViReal64(InfBytes));
}

static ViReal64 negInfinity(void)
{
   return (-posInfinity());
}

static ViReal64 notANumber(void)
{
   static const ViUInt8 NanBytes[sizeof(ViReal64)] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x7F };
   return (bytesToViReal64(NanBytes));
}

static void splitViReal64(ViReal64 val, ViPInt32 mant, ViPInt32 exp)
{
   static const ViUInt8 MantMask[sizeof(ViReal64)] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0x00 };
   static const ViUInt8 ExpMask[sizeof(ViReal64)]  = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x7F };

   ViInt16  i;
   union
   {
      ViUInt8  b[sizeof(ViReal64)];
      ViReal64 f;
   }  conv;

   conv.f   = val;
   *mant    = 0;
   *exp     = 1;

   // NOTE: the following code only works on x86 processors because of Endianess
   for (i = 0; i < sizeof(ViReal64); ++i)
   {
      *exp  &= (ExpMask[i] == (conv.b[i] & ExpMask[i]));
      *mant |= (conv.b[i] & MantMask[i]);
   }
}

static ViBoolean isNan(ViReal64 val)
{
   ViInt32 mant, exp;

   splitViReal64(val, &mant, &exp);
   return (ViBoolean)(mant && exp);
}

static ViBoolean isInf(ViReal64 val)
{
   ViInt32 mant, exp;

   splitViReal64(val, &mant, &exp);
   return (ViBoolean)(!mant && exp);
}

/*-----------------------------------------------------------------------------
 Convert infinite values.
-----------------------------------------------------------------------------*/
#define IS_NAN_VALUE       (+9.909E37)
#define IS_POS_INV_VALUE   (+9.899E37)
#define IS_NEG_INV_VALUE   (-9.899E37)

static ViReal64 convertInfinity(ViReal64 val)
{
   if      (val >= IS_NAN_VALUE)       return (notANumber());
   else if (val >= IS_POS_INV_VALUE)   return (posInfinity());
   else if (val <= IS_NEG_INV_VALUE)   return (negInfinity());
   return (val);
}

/*-----------------------------------------------------------------------------
 Check for infinite values.
-----------------------------------------------------------------------------*/
static ViStatus checkInfinity(ViReal64 val)
{
   if(isNan(val)) return (VI_INSTR_WARN_NAN);
   if(isInf(val))
   {
      if(val < 0) return (VI_INSTR_WARN_UNDERRUN);
      else        return (VI_INSTR_WARN_OVERFLOW);
   }
   return (VI_SUCCESS);
}


/*===========================================================================
 String quoting/unquoting
===========================================================================*/
/*-----------------------------------------------------------------------------
  Quote string parameter
   dst: destination buffer
   src: NUL terminated source string
  Return value: length of destination string w/o terminating NUL
-----------------------------------------------------------------------------*/
static size_t quoteString(char *dst, const char *src)
{
   size_t len;

   *dst++ = '"';
   len = 1;

   while(*src)
   {
      *dst++ = *src;
      if(*src == '"')
      {
         *dst++ = '"';
         len ++;
      }
      len ++;
      src ++;
   }

   *dst++ = '"';
   len ++;

   *dst = '\0';
   return (len);
}


/*-----------------------------------------------------------------------------
  Unquote string parameter
   str: Pointer to NUL terminated string
   quote: quote character
  Return value: passed 'str' value
-----------------------------------------------------------------------------*/
static char *unquoteString(char *str, char quote)
{
   char  *ptr, *buf, last;

   last = '\0';
   buf = str;
   ptr = str;
   while(*buf != '\0')
   {
      if((*buf == quote) && (last == quote)) buf++;
      last   = *buf;
      *ptr++ = *buf++;
   }
   *ptr = '\0';
   return (str);
}



/*===========================================================================
 Functions for managing the drivers dynamically allocated error list.
===========================================================================*/
static ViString drv_splitErrMsg(ViString str)
{
   ViChar *ptr = str;

   while(*ptr)
   {
      if(*ptr == ';') *ptr = '\0';
      else            ptr++;
   }
   return (str);
}

static void drv_dynErrlist_free(errDescrDyn_t *list)
{
   errDescrDyn_t *next;

   while(list != NULL)
   {
      next = list->next;
      free(list);
      list = next;
   }
}

static ViStatus drv_dynErrlist_lookup(errDescrDyn_t *list, ViStatus err, ViChar** pDescr)
{
   while(list != VI_NULL)
   {
      if(list->err == err)
      {
         if(pDescr != VI_NULL) *pDescr = list->descr;
         return (VI_SUCCESS);
      }
      list = list->next;
   }
   return (VI_WARN_UNKNOWN_STATUS);
}

static errDescrDyn_t *drv_dynErrlist_add(errDescrDyn_t *list, ViStatus err, ViChar* descr)
{
   errDescrDyn_t  *new;

   // Is error already in list?
   if(drv_dynErrlist_lookup(list, err, VI_NULL) == VI_SUCCESS) return (list);
   // Add new        {
   if((new = (errDescrDyn_t*)malloc(sizeof(errDescrDyn_t))) == VI_NULL) return (list);
   new->next = list;
   new->err = err;
   strncpy(new->descr, descr, DRV_BUF_SIZE);
   return new;
}



/*===========================================================================
 Init helpers
===========================================================================*/
static ViStatus drv_initClose (ViPSession instr, ViStatus stat)
{
   ViStatus  err   = VI_SUCCESS;
   ViSession rm    = VI_NULL;
   drvData_t *data = VI_NULL;

   // Get resource manager session and private data pointer
   viGetAttribute(*instr, VI_ATTR_RM_SESSION, &rm);
   viGetAttribute(*instr, VI_ATTR_USER_DATA,  &data);

   // Bring device in local mode
   viGpibControlREN(*instr, VI_GPIB_REN_DEASSERT_GTL);

   // Free private data
   if(data)
   {
      drv_dynErrlist_free(data->errList);
      free(data);
   }

   // Close sessions
   if(*instr)  err = viClose(*instr);
   if(rm)      viClose(rm);
   *instr = VI_NULL;

   return ((stat != VI_SUCCESS) ? stat : err);
}



/****************************************************************************

  End of Source file

****************************************************************************/
