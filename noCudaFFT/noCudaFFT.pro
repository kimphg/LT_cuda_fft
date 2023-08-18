QT += core
QT -= gui

CONFIG += c++11

TARGET = fft2000
CONFIG += console
CONFIG -= app_bundle

TEMPLATE = app

SOURCES += main.cpp
# The following define makes your compiler emit warnings if you use
# any feature of Qt which as been marked deprecated (the exact warnings
# depend on your compiler). Please consult the documentation of the
# deprecated API in order to know how to port your code away from it.
DEFINES += QT_DEPRECATED_WARNINGS
INCLUDEPATH += $$PWD/WpdPack/Include/
INCLUDEPATH += $$PWD/fftw/include/
#LIBPATH += $$PWD/WpdPack/Include/
DEPENDPATH += $$PWD/WpdPack/Lib/x64/
LIBS += "-L$$PWD/WpdPack/Lib/x64" -lpacket -lwpcap

DEPENDPATH += $$PWD/fftw/lib/
LIBS += "-L$$PWD/fftw/Lib/" -llibfftw3-3 -llibfftw3f-3 #-llibfftw3l-3
# You can also make your code fail to compile if you use deprecated APIs.
# In order to do so, uncomment the following line.
# You can also select to disable deprecated APIs only up to a certain version of Qt.
#DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0
INCLUDEPATH += "C:/Program Files (x86)/Windows Kits/10/Include/10.0.17134.0/ucrt"
LIBS += -L"C:/Program Files (x86)/Windows Kits/10/Lib/10.0.17134.0/ucrt/x64"
