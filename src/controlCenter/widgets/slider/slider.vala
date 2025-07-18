namespace SwayNotificationCenter.Widgets {
    public class Slider : BaseWidget {
        public override string widget_name {
            get {
                return "slider";
            }
        }

        Gtk.Label label_widget = new Gtk.Label (null);
        Gtk.Scale slider = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1);

        private double min_limit;
        private double max_limit;
        private double ? last_set;
        private bool cmd_ing = false;

        private string cmd_setter;
        private string cmd_getter;

        public Slider (string suffix, SwayncDaemon swaync_daemon, NotiDaemon noti_daemon) {
            base (suffix, swaync_daemon, noti_daemon);

            int ? round_digits = 0;

            Json.Object ? config = get_config (this);
            if (config != null) {
                string ? label = get_prop<string> (config, "label");
                label_widget.set_label (label ?? "Slider");

                cmd_setter = get_prop<string> (config, "cmd_setter") ?? "";
                cmd_getter = get_prop<string> (config, "cmd_getter") ?? "";

                int ? min = get_prop<int> (config, "min");
                int ? max = get_prop<int> (config, "max");
                int ? maxl = get_prop<int> (config, "max_limit");
                int ? minl = get_prop<int> (config, "min_limit");
                round_digits = get_prop<int> (config, "value_scale");

                if (min == null)min = 0;
                if (max == null)max = 100;
                if (round_digits == null)round_digits = 0;

                max_limit = maxl != null ? double.min (max, maxl) : max;

                min_limit = minl != null ? double.max (min, minl) : min;

                double scale = Math.pow (10, round_digits);

                min_limit /= scale;
                max_limit /= scale;

                slider.set_range (min / scale, max / scale);
            }

            slider.set_draw_value (false);
            slider.set_round_digits (round_digits);
            slider.set_hexpand (true);
            slider.set_halign (Gtk.Align.FILL);
            slider.value_changed.connect (() => {
                double value = slider.get_value ();
                if (value > max_limit)
                    value = max_limit;
                if (value < min_limit)
                    value = min_limit;

                slider.set_value (value);
                slider.tooltip_text = value.to_string ();

                if (cmd_setter != "" && last_set != value) {
                    last_set = value;
                    queue_set.begin (value);
                }
            });

            append (label_widget);
            append (slider);
        }

        public string expand_cmd (string cmd, string regex, string value) {
            try {
                Regex _regx = new Regex (Regex.escape_string (regex));
                return _regx.replace_literal (cmd, -1, 0, value);
            } catch (Error e) {
                warning ("failed to expand cmd: %s\n", e.message);
                return cmd;
            }
        }

        public async void queue_set (double value) {
            if (cmd_ing)
                return;

            cmd_ing = true;
            var cmd = expand_cmd (cmd_setter, "$value", value.to_string ());
            yield Functions.execute_command (cmd, {}, null);

            cmd_ing = false;

            // make sure the last_set is applied
            if (value != last_set) {
                yield queue_set (last_set);
            }
        }

        public async void queue_get (int retry, out string value) {
            if (cmd_ing) {
                if (retry <= 0) {
                    value = "";
                    return;
                }
                yield queue_get (retry - 1, out value);
            }

            cmd_ing = true;
            yield Functions.execute_command (cmd_getter, {}, out value);

            cmd_ing = false;
        }

        public async void on_update () {
            if (cmd_getter == "")
                return;

            string value_str = "";
            yield queue_get (4, out value_str);

            double value = double.parse (value_str);
            if (value <= max_limit && value >= min_limit) {
                last_set = value;
                slider.set_value (value);
            }
        }

        public override void on_cc_visibility_change (bool value) {
            if (value)
                on_update.begin ();
        }
    }
}
