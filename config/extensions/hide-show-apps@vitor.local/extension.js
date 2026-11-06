import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class HideShowAppsExtension extends Extension {
    enable() {
        this._button = Main.overview.dash._showAppsIcon;
        this._button.hide();
        // o dash tenta mostrar de novo em alguns momentos; mantém escondido
        this._signal = this._button.connect('notify::visible', () => {
            if (this._button.visible)
                this._button.hide();
        });
    }

    disable() {
        if (this._signal)
            this._button.disconnect(this._signal);
        this._button?.show();
        this._button = null;
        this._signal = null;
    }
}
