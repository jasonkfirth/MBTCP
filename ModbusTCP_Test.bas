'ModbusTCP Test program
'This program tests and demonstrates the modbusTCP library for FreeBASIC

' #define MBTCP_Debug
' #Define IntenseMBP_RetrieveDiscreteInput_Debug

#include "ModbusTCP.bi"

'Initialise the MBTCP library
print "Initializing MBTCP"
MBTCP_Init ()

print "Connecting to 192.168.4.218"
MBTCP_Connect ("192.168.4.218")

dim a as integer

print "Coil Retrieval Test:"
for a = 1 to 5
    print "Coil ";a;" is:";MBTCP_RetrieveCoil(a);"                         "
      
next a

print "Discrete Input Retrieval Test:"
for a = 1 to 5
    print "Coil ";a;" is:";MBTCP_RetrieveDiscreteInput(a);"                         "
      
next a

print "Register Retrieval Test:"
for a = 1 to 5
    print "Register ";a;" is:";MBTCP_RetrieveRegister(a);"                         "
next a
print
print "Floating Point Retrieve "; MBTCP_RetrieveFloatRegister(310)
print
print "Long Value Retrieve "; MBTCP_RetrieveLongRegister(310)


dim floating as single
dim intermediary as long


sleep
MBTCP_Disconnect( )

MBTCP_doShutdown( )

sleep