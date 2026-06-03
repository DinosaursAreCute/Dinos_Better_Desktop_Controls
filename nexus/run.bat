@echo off
cd /d "%~dp0"

:: Install dependencies if needed
python -m pip install -q -r requirements.txt

:: Launch the dashboard
python nexus_dashboard.py
