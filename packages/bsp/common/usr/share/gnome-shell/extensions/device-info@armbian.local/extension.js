// Shows "hostname · primary IPv4" in the GNOME top bar, refreshed periodically.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const REFRESH_SECONDS = 15;

export default class DeviceInfoExtension extends Extension {
    enable() {
        this._indicator = new PanelMenu.Button(0.0, 'Device Info', true);
        this._label = new St.Label({
            text: GLib.get_host_name(),
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._indicator.add_child(this._label);
        Main.panel.addToStatusArea('armbian-device-info', this._indicator, 0, 'right');

        this._refresh();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = null;
        }
        this._indicator?.destroy();
        this._indicator = null;
        this._label = null;
    }

    _refresh() {
        let host = GLib.get_host_name();
        let ip = '';
        try {
            let [ok, out] = GLib.spawn_command_line_sync('ip -4 route get 1.0.0.1');
            if (ok) {
                const match = out.toString().match(/src (\S+)/);
                if (match)
                    ip = match[1];
            }
        } catch {
            // offline or no default route: show hostname only
        }
        if (this._label)
            this._label.text = ip ? `${host} · ${ip}` : host;
    }
}
