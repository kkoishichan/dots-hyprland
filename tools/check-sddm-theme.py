#!/usr/bin/env python3
"""Exercise the theme against mock SDDM models; never authenticates or powers off."""
import os
os.environ['QT_QPA_PLATFORM']='offscreen'
os.environ['QT_QPA_PLATFORMTHEME']=''
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
os.environ.setdefault('QT_QUICK_CONTROLS_STYLE', 'Basic')
os.environ.setdefault('QML_XHR_ALLOW_FILE_READ', '1')
import sys
from pathlib import Path
from PySide6.QtCore import (QAbstractListModel, QModelIndex, QObject, Property, QSettings,
                            Signal, Slot, Qt, QUrl, QMetaObject, qInstallMessageHandler)
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

errors=[]
def message(kind, context, text):
    if 'Fatal' in str(kind): print(text, file=sys.stderr, flush=True)
    if any(word in text for word in ['ReferenceError', 'TypeError', 'is not a type', 'is not installed', 'assign', 'required property']):
        errors.append(text)
        print(text, file=sys.stderr)
qInstallMessageHandler(message)

class Settings(QObject):
    def __init__(self, values): super().__init__(); self.values=values
    def value(self, key): return self.values.get(key)
    @Slot(str, result=bool)
    def boolValue(self, key): return str(self.value(key)).lower() == 'true'
    @Slot(str, result=float)
    def realValue(self, key): return float(self.value(key))
    @Slot(str, result=int)
    def intValue(self, key): return int(float(self.value(key)))

class Model(QAbstractListModel):
    def __init__(self, names): super().__init__(); self.names=names
    def rowCount(self, parent=QModelIndex()): return len(self.names)
    def roleNames(self): return {Qt.UserRole+1:b'name'}
    def data(self, index, role=Qt.DisplayRole):
        return self.names[index.row()] if index.isValid() and role==Qt.UserRole+1 else None
    @Property(int, constant=True)
    def lastIndex(self): return 0
    @Property(str, constant=True)
    def lastUser(self): return self.names[0]

class Greeter(QObject):
    loginFailed=Signal()
    loginSucceeded=Signal()
    def __init__(self): super().__init__(); self.requests=[]; self.power=[]
    @Property(bool, constant=True)
    def canPowerOff(self): return True
    @Property(bool, constant=True)
    def canSuspend(self): return True
    @Property(bool, constant=True)
    def canReboot(self): return True
    @Slot(str,str,int)
    def login(self, user, password, session): self.requests.append((user,password,session))
    @Slot()
    def suspend(self): self.power.append('sleep')
    @Slot()
    def powerOff(self): self.power.append('poweroff')
    @Slot()
    def reboot(self): self.power.append('reboot')

class Keyboard(QObject):
    currentLayoutChanged=Signal()
    capsLockChanged=Signal()
    def __init__(self): super().__init__(); self.current=0; self.caps=False
    @Property(bool, constant=True)
    def enabled(self): return True
    @Property(bool, notify=capsLockChanged)
    def capsLock(self): return self.caps
    @capsLock.setter
    def capsLock(self, value):
        self.caps=value
        self.capsLockChanged.emit()
    @Property(list, constant=True)
    def layouts(self): return [{'shortName':'us'}, {'shortName':'de'}]
    @Property(int, notify=currentLayoutChanged)
    def currentLayout(self): return self.current
    @currentLayout.setter
    def currentLayout(self, value):
        self.current=value
        self.currentLayoutChanged.emit()

app=QGuiApplication([])
theme=Path(sys.argv[1]).resolve()
config_values={}
for file in [theme/'theme.conf',theme/'theme.conf.user']:
    ini=QSettings(str(file),QSettings.IniFormat)
    for key in ini.allKeys():config_values[key]=ini.value(key)
SettingsType=type("ThemeSettings",(Settings,),{key:Property(str,lambda self,k=key:str(self.values[k]),constant=True) for key in config_values})
config=SettingsType(config_values)
users=Model(['koishi','second-user']);sessions=Model(['Hyprland','Xfce'])
greeter=Greeter();keyboard=Keyboard()
view=QQuickView();view.setResizeMode(QQuickView.SizeRootObjectToView)
for key,value in [('config',config),('userModel',users),('sessionModel',sessions),('sddm',greeter),('keyboard',keyboard),('primaryScreen',True)]:
    view.rootContext().setContextProperty(key,value)
view.setSource(QUrl.fromLocalFile(str(theme/'Main.qml')))
assert view.status()==QQuickView.Ready,[e.toString() for e in view.errors()]
view.resize(1280,800);view.show();QTest.qWait(200)
root=view.rootObject()
password=root.findChild(QObject,'passwordField')
user=root.findChild(QObject,'userSelector');session=root.findChild(QObject,'sessionSelector')
assert all(x is not None for x in (password,user,session))
assert password.property('activeFocus'),'Password input does not receive initial focus'
assert root.findChild(QObject,'fingerprintIcon') is None
assert password.property('placeholderText')=='输入密码'
keyboard.capsLock=True;QTest.qWait(30)
assert password.property('placeholderText')=='大写锁定已开启','Caps Lock must be visible before typing a password'
keyboard.capsLock=False;QTest.qWait(30)
assert password.property('placeholderText')=='输入密码'
user.setProperty('currentIndex',1);session.setProperty('currentIndex',1);QTest.qWait(30)
password.setProperty('text','test-only-password')
QMetaObject.invokeMethod(password,'accepted')
assert greeter.requests==[('second-user','test-only-password',1)],'Selected identity/session was not passed to SDDM'
assert root.property('authenticating') and password.property('text')==''
assert not password.property('enabled')
QMetaObject.invokeMethod(root,'submit')
assert len(greeter.requests)==1,'Duplicate login was submitted while authentication was pending'
greeter.loginFailed.emit();QTest.qWait(350)
assert not root.property('authenticating') and root.property('loginFailed')
assert password.property('placeholderText')=='密码错误'
assert password.property('text')=='' and password.property('enabled') and password.property('activeFocus')
password.setProperty('text','retry')
assert not root.property('loginFailed')
QTest.keyClick(view,Qt.Key_Escape)
assert password.property('text')==''
# Empty passwords use the same authentication and failure feedback as any password.
QMetaObject.invokeMethod(password,'accepted')
assert greeter.requests[-1]==('second-user','',1)
assert root.property('authenticating')
assert password.property('placeholderText')=='输入密码'
greeter.loginFailed.emit();QTest.qWait(350)
assert password.property('enabled') and password.property('activeFocus')
assert root.property('loginFailed'),'Empty password failure must show the normal password error'
assert not root.property('authenticating')
assert password.property('placeholderText')=='密码错误'
# The layout control displays the selected code and cycles available layouts.
layout_button=root.findChild(QObject,'keyboardButton')
assert layout_button is not None and layout_button.property('visible')
assert layout_button.property('labelText')=='US'
QMetaObject.invokeMethod(layout_button,'clicked')
assert keyboard.currentLayout==1 and layout_button.property('labelText')=='DE'
QMetaObject.invokeMethod(layout_button,'clicked')
# Opening the actual delegates catches role and popup errors hidden at startup.
for selector in [user,session]:
    popup=selector.findChild(QObject,'choicePopup')
    assert popup is not None
    popup.setProperty('visible',True);QTest.qWait(100)
    assert popup.property('visible')
    popup.setProperty('visible',False)
for name in ['sleepButton','powerButton','rebootButton']:
    button=root.findChild(QObject,name)
    assert button is not None
    QMetaObject.invokeMethod(button,'clicked')
assert greeter.power==['sleep','poweroff','reboot'],greeter.power
assert not errors,errors
if len(sys.argv)>2:
    # Save the idle login state, rather than the simulated authentication error.
    root.setProperty('loginFailed',False)
    user.setProperty('currentIndex',0);session.setProperty('currentIndex',0)
    QTest.qWait(600)
    assert view.grabWindow().save(sys.argv[2]),'Could not save theme preview'
view.setSource(QUrl());view.close()
print('PASS: selection, password submission/clearing, pending guard, password failure/retry, empty password failure, Escape, keyboard layouts, popups and power routing (mock backend).')
