# helpbook
Escaping the output:
esc_html() - when rendering something inside html code
esc_url() - when rendering url ( <img src="<?php echo esc_url ($url); ?>" />
esc_js() <a href="#" onlick="<?php echo esc_js( $custom_js ); ?>" > Click me </a>
esc_attr()
esc_textarea()
