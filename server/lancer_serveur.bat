@echo off
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
title Serveur Arcanes ^& Lames
cd /d "%~dp0"
echo Lancement du serveur communautaire : port 7778 (TCP) + mises a jour sur 7779 (HTTP)
python lobby_server.py --port 7778
pause
