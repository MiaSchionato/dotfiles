@echo off
rem The vim-like mode as one letter, for the yasb widget (2026-10-08).
rem komokana writes kanata's current layer to this file. INSERT is I (the base
rem layers: base, premiere, zen); a momentary layer (CapsLock, accents) prints
rem nothing, so the widget hides for that moment.
set "L="
set /p L=<"%LOCALAPPDATA%\Temp\kanata_layer"
if "%L%"=="window" echo W
if "%L%"=="goto" echo G
if "%L%"=="move" echo M
if "%L%"=="resize" echo R
if "%L%"=="cmdline" echo :
if "%L%"=="base" echo I
if "%L%"=="premiere" echo I
if "%L%"=="zen" echo I
