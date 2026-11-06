// página inicial padrão do Firefox (sobrescreve start.fedoraproject.org do Fedora)
user_pref("browser.startup.homepage", "about:home");
user_pref("browser.startup.page", 3); // 3 = restaurar abas da sessão anterior
// restaurar abas mesmo quando o Firefox foi fechado à força (logout/desligar)
user_pref("browser.sessionstore.resume_from_crash", true);
user_pref("browser.sessionstore.max_resumed_crashes", 10);
// não perguntar ao fechar com várias abas
user_pref("browser.warnOnQuit", false);
user_pref("browser.tabs.warnOnClose", false);
