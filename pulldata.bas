'ModbusTCP Test program
'This program tests and demonstrates the modbusTCP library for FreeBASIC

' #define MBTCP_Debug
' #Define IntenseMBP_RetrieveDiscreteInput_Debug

#include "ModbusTCP.bi"

'Initialise the MBTCP library
print "Initializing MBTCP"
MBTCP_Init ()

print "Connecting to ";"192.168.4.126"
MBTCP_Connect ("192.168.4.126")

MBP_ZeroOffset = 1
MBP_UnitID = 1

dim a as short
dim b as integer

print "Pulling Register States"
for a = 4000 to 32000
    MBTCP_Connect ("192.168.4.126")
    print  "R,";a;",";MBTCP_RetrieveRegister(a) ;" Float:";MBTCP_RetrieveFloatRegister(a)
    MBTCP_Disconect( )
    sleep 250
next a
print "Complete. Press enter to continue."


sleep
MBTCP_Disconect( )

MBTCP_doShutdown( )

sleep