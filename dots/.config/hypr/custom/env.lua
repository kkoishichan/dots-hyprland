-- Graphical session locale. /etc/locale.conf stays en_US.UTF-8, so TTYs remain English.
hl.env("LANG", "zh_CN.UTF-8")
hl.env("LC_ALL", "zh_CN.UTF-8")

hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULES", "fcitx;ibus")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")
