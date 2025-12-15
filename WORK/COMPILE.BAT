rescan
cls
SET ML=/nologo /W3 /Flmain /Sa /Sf /Sg
MASM /T /LA /C /D main.asm
LINK /NOLOGO main.obj;