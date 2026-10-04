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
    @Property(bool, constant=True)
    def enabled(self): return False
    @Property(bool, constant=True)
    def capsLock(self): return False
    @Property(list, constant=True)
    def layouts(self): return []

app=QGuiApplication([])
theme=Path(sys.argv[1]).resolve()
config_values={}
for file in [theme/'theme.conf',theme/'theme.conf.user']:
    ini=QSettings(str(file),QSettings.IniFormat)
    for key in ini.allKeys():config_values[key]=ini.value(key)
SettingsType=type("ThemeSettings",(Settings,),{key:Property(str,lambda self,k=key:str(self.values[k]),constant=True) for key in config_values})
config=SettingsType(config_values)
users=Model(['koishi','second-user']);sessions=Model(['Hyprland','Hyprland (uwsm-managed)','Sway'])
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
user.setProperty('currentIndex',1);session.setProperty('currentIndex',2);QTest.qWait(30)
password.setProperty('text','test-only-password')
QMetaObject.invokeMethod(password,'accepted')
assert greeter.requests==[('second-user','test-only-password',2)],'Selected identity/session was not passed to SDDM'
assert root.property('authenticating') and password.property('text')==''
assert not password.property('enabled')
QMetaObject.invokeMethod(root,'submit')
assert len(greeter.requests)==1,'Duplicate login was submitted while authentication was pending'
greeter.loginFailed.emit();QTest.qWait(350)
assert not root.property('authenticating') and root.property('loginFailed')
assert password.property('text')=='' and password.property('enabled') and password.property('activeFocus')
password.setProperty('text','retry')
assert not root.property('loginFailed')
QTest.keyClick(view,Qt.Key_Escape)
assert password.property('text')==''
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
view.setSource(QUrl());view.close()
print('PASS: selection, password submission/clearing, pending guard, failure/retry, Escape, popups and power routing (mock backend).')
