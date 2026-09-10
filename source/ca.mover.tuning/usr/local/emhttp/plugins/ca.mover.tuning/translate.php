#!/usr/bin/php -q
<?php
// CLI helper: translate.php TEMPLATE [ARG ...]
// Prints TEMPLATE in the GUI language, read from languages/<locale>.txt of this plugin, with each %s
// filled from the arguments; English when no language applies.
$docroot = '/usr/local/emhttp';
$template = $argv[1] ?? '';
$args = array_slice($argv, 2);

function fill_template($text, $args) {
    $from = 0;
    foreach ($args as $arg) {
        $pos = strpos($text, '%s', $from);
        if ($pos === false) {
            break;
        }
        $text = substr_replace($text, $arg, $pos, 2);
        $from = $pos + strlen($arg);
    }
    return $text;
}

$text = $template;
if (file_exists("$docroot/webGui/include/Translations.php") === true) {
    $dynamix = file_exists('/boot/config/plugins/dynamix/dynamix.cfg') === true ? parse_ini_file('/boot/config/plugins/dynamix/dynamix.cfg', true) : [];
    $login_locale = $dynamix['display']['locale'] ?? '';
    $_SESSION['locale'] = $login_locale;
    $_SERVER['REQUEST_URI'] = 'movertuning';
    require_once "$docroot/webGui/include/Translations.php";
    $moverTuningLanguageFile = "$docroot/plugins/ca.mover.tuning/languages/$login_locale.txt";
    if (preg_match('/^[a-z]{2}_[A-Z]{2}$/', $login_locale) === 1 && file_exists($moverTuningLanguageFile) === true) {
        $language = array_merge($language, parse_lang_file($moverTuningLanguageFile));
    }
    $translated = html_entity_decode(strip_tags(_($template)), ENT_QUOTES | ENT_HTML5);
    // a translation that lost or gained a placeholder would misplace the values
    if (substr_count($translated, '%s') === substr_count($template, '%s')) {
        $text = $translated;
    }
}
echo fill_template($text, $args);
