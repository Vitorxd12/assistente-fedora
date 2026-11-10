import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';

// Combina com `hide_window_decorations titlebar-only` no kitty.conf: o kitty
// fica sem barra de título e esta extensão desenha só os três botões, no canto
// superior direito, sobre o terminal. Arrastar pela faixa do topo (a área do
// padding superior, sem cobrir texto) move a janela; duplo
// clique na faixa maximiza; Super+arrastar também funciona.

const WM_CLASS = 'kitty';
const MARGIN = 6;
const STRIP = 24; // altura da faixa de arrasto = padding superior do kitty.conf

const BUTTONS = [
    ['window-minimize-symbolic', w => w.minimize()],
    ['window-maximize-symbolic', w => {
        if (w.is_maximized())
            w.unmaximize();
        else
            w.maximize();
    }],
    ['window-close-symbolic', w => w.delete(global.get_current_time())],
];

// Mutter 51: begin_grab_op recebe um ClutterSprite (ponteiro/toque), não mais
// dispositivo + sequência.
function startMove(win, event) {
    const backend = global.stage.context.get_backend();
    const sprite = backend.get_sprite(global.stage, event) ?? backend.get_pointer_sprite(global.stage);
    win.begin_grab_op(Meta.GrabOp.MOVING, sprite, event.get_time(), null);
}

export default class KittyWindowButtons extends Extension {
    enable() {
        this._boxes = new Map(); // Meta.Window -> {box, strip, ids}
        this._timeouts = new Set();
        this._displayId = global.display.connect('window-created', (_d, win) => this._track(win));
        // janelas já abertas
        for (const actor of global.get_window_actors())
            this._track(actor.meta_window);
    }

    disable() {
        global.display.disconnect(this._displayId);
        for (const id of this._timeouts)
            GLib.source_remove(id);
        this._timeouts = null;
        for (const win of [...this._boxes.keys()])
            this._untrack(win);
        this._boxes = null;
    }

    _isKitty(win) {
        return win.get_wm_class() === WM_CLASS &&
            win.get_window_type() === 0; // Meta.WindowType.NORMAL
    }

    _track(win) {
        // a classe pode demorar a ser definida em janelas Wayland novas
        const attach = () => {
            if (this._boxes?.has(win) || !this._isKitty(win))
                return GLib.SOURCE_REMOVE;
            const actor = win.get_compositor_private();
            if (!actor)
                return GLib.SOURCE_REMOVE;

            // faixa transparente no topo: arrastar move a janela, duplo clique maximiza
            const strip = new St.Widget({reactive: true, height: STRIP});
            strip.connect('button-press-event', (_a, event) => {
                if (event.get_button() !== Clutter.BUTTON_PRIMARY)
                    return Clutter.EVENT_PROPAGATE;
                // duplo clique calculado na mão (Clutter não expõe mais a contagem)
                const now = event.get_time();
                const dbl = now - (this._lastStripClick ?? -1e9) < 400;
                this._lastStripClick = dbl ? -1e9 : now;
                if (dbl) {
                    if (win.is_maximized())
                        win.unmaximize();
                    else
                        win.maximize();
                } else {
                    startMove(win, event);
                }
                return Clutter.EVENT_STOP;
            });
            actor.add_child(strip);

            const box = new St.BoxLayout({
                style: 'spacing: 4px; padding: 2px 4px; border-radius: 12px;' +
                       'background-color: rgba(0,0,0,0.35);',
                reactive: true,
                opacity: 170,
            });
            box.connect('enter-event', () => box.ease({opacity: 255, duration: 120}));
            box.connect('leave-event', () => box.ease({opacity: 170, duration: 120}));

            // sem handler de clique na caixa: o clique nos botões subia até ela,
            // que iniciava o arrasto e engolia o "clicked" (fechar/minimizar).
            for (const [icon, action] of BUTTONS) {
                const isClose = icon === 'window-close-symbolic';
                const btn = new St.Button({
                    child: new St.Icon({icon_name: icon, icon_size: 14}),
                    style: 'padding: 3px 6px; border-radius: 10px; color: white;',
                    reactive: true,
                    can_focus: false,
                });
                btn.connect('enter-event', () => btn.set_style(
                    `padding: 3px 6px; border-radius: 10px; color: white; background-color: ${
                        isClose ? 'rgba(230,60,60,0.9)' : 'rgba(255,255,255,0.2)'};`));
                btn.connect('leave-event', () => btn.set_style(
                    'padding: 3px 6px; border-radius: 10px; color: white;'));
                btn.connect('clicked', () => action(win));
                box.add_child(btn);
            }
            actor.add_child(box);

            const place = () => {
                if (!box.get_parent())
                    return;
                const frame = win.get_frame_rect();
                const buf = win.get_buffer_rect();
                strip.set_position(frame.x - buf.x, frame.y - buf.y);
                strip.set_width(frame.width);
                strip.visible = !win.is_fullscreen();
                const [w] = box.get_size();
                box.set_position(
                    frame.x - buf.x + frame.width - w - MARGIN,
                    frame.y - buf.y + MARGIN);
                box.visible = !win.is_fullscreen();
            };
            const ids = [
                win.connect('size-changed', place),
                win.connect('position-changed', place),
                win.connect('notify::fullscreen', place),
                win.connect('unmanaged', () => this._forget(win)),
            ];
            this._boxes.set(win, {box, strip, ids});
            place();
            // largura dos botões só é conhecida após o primeiro layout
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => { place(); return GLib.SOURCE_REMOVE; });
            return GLib.SOURCE_REMOVE;
        };
        attach();
        if (this._boxes.has(win) || !this._isKitty(win) && win.get_wm_class())
            return;
        // classe Wayland ainda não definida: tenta uma vez mais
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            this._timeouts.delete(id);
            return attach();
        });
        this._timeouts.add(id);
    }

    // janela fechada: o ator já foi destruído junto; só limpa o registro
    _forget(win) {
        this._boxes?.delete(win);
    }

    _untrack(win) {
        const entry = this._boxes.get(win);
        if (!entry)
            return;
        for (const id of entry.ids)
            win.disconnect(id);
        entry.box.destroy();
        entry.strip.destroy();
        this._boxes.delete(win);
    }
}
