@echo off
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
title Publier une version - Arcanes ^& Lames
cd /d "%~dp0"
echo Publie une nouvelle version sur le serveur officiel (export + envoi sur le VPS).
set /p VERSION=Numero de la nouvelle version (ex. 1.1.0) : 
set /p NOTES=Resume (facultatif, sinon le titre de data\patchnotes.json) : 
python publish_update.py %VERSION% "%NOTES%"
pause
