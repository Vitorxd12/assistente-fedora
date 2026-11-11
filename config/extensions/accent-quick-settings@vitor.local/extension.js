import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ACCENTS = [
    {id: 'blue', label: 'Azul', hex: '#3584e4'},
    {id: 'teal', label: 'Turquesa', hex: '#2190a4'},
    {id: 'green', label: 'Verde', hex: '#3a944a'},
    {id: 'yellow', label: 'Amarelo', hex: '#c88800'},
    {id: 'orange', label: 'Laranja', hex: '#ed5b00'},
    {id: 'red', label: 'Vermelho', hex: '#e62d42'},
    {id: 'pink', label: 'Rosa', hex: '#d56199'},
    {id: 'purple', label: 'Roxo', hex: '#9141ac'},
    {id: 'slate', label: 'Ardósia', hex: '#6f8396'},
];

const HIDDEN_ICONS = new Set([
    'airplane-mode-symbolic',
    'dark-mode-symbolic',
    'notifications-disabled-symbolic',
]);

const AccentToggle = GObject.registerClass(
class AccentToggle extends QuickSettings.QuickMenuToggle {
    constructor() {
        super({
            title: 'Cor de destaque',
            subtitle: '',
            iconName: 'applications-graphics-symbolic',
            toggleMode: false,
        });

        this._settings = new Gio.Settings({
            schema_id: 'org.gnome.desktop.interface',
        });
        this._settings.connectObject(
            'changed::accent-color', () => this._sync(), this);

        this.menu.setHeader(
            'applications-graphics-symbolic',
            'Cor de destaque',
            'Escolha a cor do GNOME');

        this._items = ACCENTS.map(accent => {
            const item = new PopupMenu.PopupMenuItem(accent.label);
            const swatch = new St.Icon({
                icon_name: 'media-record-symbolic',
                style: `color: ${accent.hex};`,
            });
            item.insert_child_at_index(swatch, 1);
            item.connect('activate', () => {
                this._settings.set_string('accent-color', accent.id);
                this.menu.close();
            });
            this.menu.addMenuItem(item);
            return {accent, item};
        });

        this.connect('clicked', () => this.menu.open());
        this._sync();
    }

    _sync() {
        const current = this._settings.get_string('accent-color');
        const accent = ACCENTS.find(option => option.id === current);
        this.subtitle = accent?.label ?? current;
        this._items.forEach(({accent: option, item}) => {
            item.setOrnament(option.id === current
                ? PopupMenu.Ornament.DOT
                : PopupMenu.Ornament.NONE);
        });
    }
});

const KeepAwakeToggle = GObject.registerClass(
class KeepAwakeToggle extends QuickSettings.QuickMenuToggle {
    constructor() {
        super({
            title: 'Tela sempre ligada',
            subtitle: 'Desativado',
            iconName: 'display-brightness-symbolic',
            toggleMode: true,
        });
        this._cookie = 0;
        this._busy = false;
        this.connect('notify::checked', () => this._setInhibited(this.checked));
    }

    _setInhibited(enabled) {
        if (this._busy)
            return;
        if (enabled) {
            const session = Gio.DBus.session;
            this._busy = true;
            session.call(
                'org.gnome.SessionManager',
                '/org/gnome/SessionManager',
                'org.gnome.SessionManager',
                'Inhibit',
                new GLib.Variant('(susu)', ['assistente-fedora', 0, 'Tela sempre ligada', 8]),
                new GLib.VariantType('(u)'),
                Gio.DBusCallFlags.NONE,
                -1,
                null,
                (connection, result) => {
                    this._busy = false;
                    try {
                        this._cookie = connection.call_finish(result).deep_unpack()[0];
                        if (!this.checked) {
                            this._uninhibit();
                            this.subtitle = 'Desativado';
                        } else {
                            this.subtitle = 'Ativado';
                        }
                    } catch (error) {
                        this.checked = false;
                        this.subtitle = 'Não foi possível ativar';
                        logError(error, 'Falha ao inibir a inatividade da tela');
                    }
                });
        } else {
            this._uninhibit();
            this.subtitle = 'Desativado';
        }
    }

    _uninhibit() {
        if (!this._cookie)
            return;
        Gio.DBus.session.call(
            'org.gnome.SessionManager', '/org/gnome/SessionManager',
            'org.gnome.SessionManager', 'Uninhibit',
            new GLib.Variant('(u)', [this._cookie]), null,
            Gio.DBusCallFlags.NONE, -1, null, null);
        this._cookie = 0;
    }

    destroy() {
        this._uninhibit();
        super.destroy();
    }
});

const AccentIndicator = GObject.registerClass(
class AccentIndicator extends QuickSettings.SystemIndicator {
    constructor() {
        super();
        this.quickSettingsItems.push(new AccentToggle());
        this.quickSettingsItems.push(new KeepAwakeToggle());
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class AccentQuickSettingsExtension extends Extension {
    enable() {
        const quickSettings = Main.panel.statusArea.quickSettings;
        this._hiddenItems = [];

        // GNOME 51 exposes these built-in tiles in the Quick Settings grid.
        // Keep their actors available for GNOME while hiding their grid entries.
        const grid = quickSettings.menu?._grid;
        for (const item of grid?.get_children() ?? []) {
            if (!HIDDEN_ICONS.has(item.iconName))
                continue;

            const hidden = {
                item,
                visible: item.visible,
                signal: 0,
            };
            hidden.signal = item.connect('notify::visible', () => {
                if (item.visible)
                    item.hide();
            });
            item.hide();
            this._hiddenItems.push(hidden);
        }

        this._indicator = new AccentIndicator();
        quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        for (const {item, visible, signal} of this._hiddenItems ?? []) {
            item.disconnect(signal);
            item.visible = visible;
        }
        this._hiddenItems = null;

        this._indicator?.destroy();
        this._indicator = null;
    }
}
