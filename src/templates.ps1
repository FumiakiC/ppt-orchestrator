$script:HtmlTemplates = @{
    # Shared HTML header + CSS + polling script.
    # Runtime tokens: %%TITLE%% (page title), %%BGCOLOR%% (compat, no visual effect).
    HtmlHeader = @'
%%BUILD_VIEW_HTMLHEADER%%
'@

    # Now Presenting view (remote control). Runtime token: %%DECK%% (HtmlEncoded deck name).
    NowPlayingView = @'
%%BUILD_VIEW_NOWPLAYING%%
'@

    # Lobby view (deck queue).
    # Runtime tokens: %%LOBBY_START_BTN%%, %%LOBBY_NEXT_TEXT%%, %%LOBBY_LIST%%.
    LobbyView = @'
%%BUILD_VIEW_LOBBY%%
'@

    # Post-presentation dialog.
    # Runtime tokens: %%DIALOG_FILE%%, %%DIALOG_NEXT_CLS%%, %%DIALOG_NEXT_STATE%%, %%DIALOG_NEXT_LABEL%%.
    DialogView = @'
%%BUILD_VIEW_DIALOG%%
'@

    # Polling call-site for Lobby/Dialog pages (startPolling function is defined in HtmlHeader).
    PollingScript = @'
    <script>
        window.startPolling(['waiting'], '/', { defaultDelay: 300, statusRedirects: { 'stopping': '/exit' } });
    </script>
'@

    # Hold-to-charge CSS moved to main.css; JS unified into hold.js (injected via HtmlHeader).
    # Kept as empty string so existing append in ui-console.ps1 is harmless.
    HoldToConfirmScript = @'
'@

    # Processing view.
    ProcessingView = @'
%%BUILD_VIEW_PROCESSING%%
'@

    # Exit view.
    ExitView = @'
%%BUILD_VIEW_EXIT%%
'@

    # PIN authentication view (standalone, does not use HtmlHeader).
    # Runtime tokens: %%BGCOLOR%% (compat, no visual effect), %%AUTH_ERROR%% ("error" or "").
    AuthView = @'
%%BUILD_VIEW_AUTH%%
'@
}
