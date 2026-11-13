import { webview } from '@kit.ArkWeb';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { i18n } from '@kit.LocalizationKit';
import { CLIENT_ORIGIN, CLIENT_URL } from '../Config/Endpoint';
import { SHELL_LANGUAGES, SHELL_LANGUAGE_NAMES, shellText } from '../Config/ShellCopy';

// Pure policy shared by normal navigation and user-triggered window.open.
export function navigationKind(target: string, origin: string, mainFrame: boolean, gesture: boolean): string {
  if (target === 'about:blank' && origin.length === 0) {
    return 'internal';
  }
  if (/[\s\\\x00-\x1f\x7f]/.test(target)) {
    return 'blocked';
  }
  try {
    const parsed = url.URL.parseURL(target);
    if ((parsed.protocol !== 'http:' && parsed.protocol !== 'https:') || parsed.hostname.length === 0 ||
      parsed.username.length > 0 || parsed.password.length > 0 || parsed.port === '0') {
      return 'blocked';
    }
    if (origin.length > 0 && parsed.origin === origin) {
      return 'internal';
    }
    return origin.length > 0 && mainFrame && gesture ? 'external' : 'blocked';
  } catch (_) {
    return 'blocked';
  }
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private loadError: string = '';
  @State private shellLanguage: number = 0;
  @State private shellTheme: number = 0;
  private controllerAttached: boolean = false;

  aboutToAppear(): void {
    if (CLIENT_URL.length === 0) {
      this.loadError = 'unconfigured';
    }
  }

  private locale(): string {
    if (this.shellLanguage > 0) {
      return SHELL_LANGUAGES[this.shellLanguage - 1];
    }
    const system = i18n.System.getSystemLanguage().toLowerCase();
    if (system.startsWith('zh')) {
      return system.includes('hant') || system.includes('tw') || system.includes('hk') ? 'zh-Hant' : 'zh';
    }
    const language = system.split('-')[0];
    return SHELL_LANGUAGES.includes(language) ? language : 'en';
  }

  private copy(key: string): string {
    return shellText(key, this.locale());
  }

  private surface(): ResourceColor {
    return this.shellTheme === 1 ? '#FBF7F0' : this.shellTheme === 2 ? '#191612' : $r('sys.color.ohos_id_color_background');
  }

  private foreground(): ResourceColor {
    return this.shellTheme === 1 ? '#352A24' : this.shellTheme === 2 ? '#F4EDE4' : $r('sys.color.ohos_id_color_text_primary');
  }

  private retry(): void {
    if (!this.controllerAttached || CLIENT_URL.length === 0) {
      return;
    }
    this.loadError = '';
    this.controller.loadUrl(CLIENT_URL);
  }

  private browserFailureMessage(): string {
    const language = this.locale().toLowerCase();
    if (language.startsWith('zh')) {
      return language.includes('hant') || language.includes('tw') || language.includes('hk')
        ? '無法開啟瀏覽器，請檢查系統預設瀏覽器後重試。'
        : '无法打开浏览器，请检查系统默认浏览器后重试。';
    }
    const messages = new Map<string, string>([
      ['bo', 'ལྟ་བཤེར་ཆས་ཁ་ཕྱེ་མ་ཐུབ། མ་ལག་གི་ལྟ་བཤེར་ཆས་ལ་བརྟག་དཔྱད་གནང་།'],
      ['en', 'Unable to open the browser. Check the system default browser and retry.'],
      ['ja', 'ブラウザを開けません。既定のブラウザを確認して再試行してください。'],
      ['fr', 'Impossible d’ouvrir le navigateur. Vérifiez le navigateur par défaut.'],
      ['es', 'No se pudo abrir el navegador. Revisa el navegador predeterminado.'],
      ['de', 'Browser konnte nicht geöffnet werden. Bitte Standardbrowser prüfen.'],
      ['ru', 'Не удалось открыть браузер. Проверьте браузер по умолчанию.'],
      ['ko', '브라우저를 열 수 없습니다. 기본 브라우저를 확인해 주세요.']
    ]);
    return messages.get(language.split('-')[0]) || messages.get('en') || '';
  }

  private async openExternal(target: string): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: target
      });
    } catch (_) {
      promptAction.showToast({ message: this.browserFailureMessage() });
    }
  }

  build() {
    Stack() {
      Web({ src: CLIENT_URL.length > 0 ? CLIENT_URL : 'about:blank', controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .mixedMode(MixedMode.None)
        .multiWindowAccess(true)
        .allowWindowOpenMethod(true)
        .onControllerAttached(() => { this.controllerAttached = true; })
        .onLoadIntercept((event) => {
          if (!event) { return true; }
          const target = event.data.getRequestUrl();
          const kind = navigationKind(target, CLIENT_ORIGIN, event.data.isMainFrame(),
            event.data.isRequestGesture() && !event.data.isRedirect());
          if (kind === 'external') {
            this.openExternal(target);
          }
          return kind !== 'internal';
        })
        .onWindowNew((event) => {
          if (!event) { return; }
          // Always release the new-window request; no embedded popup is created.
          event.handler.setWebController(null);
          if (!event.isUserTrigger) { return; }
          const kind = navigationKind(event.targetUrl, CLIENT_ORIGIN, true, true);
          if (kind === 'external') {
            this.openExternal(event.targetUrl);
          } else if (kind === 'internal' && this.controllerAttached) {
            this.controller.loadUrl(event.targetUrl);
          }
        })
        .onErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            this.loadError = 'network';
          }
        })
        .onHttpErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            this.loadError = 'unavailable';
          }
        })
        // ArkWeb defaults to rejecting invalid certificates. No handler bypasses TLS validation.
        .onShowFileSelector((event) => {
          if (!event) { return false; }
          const result = event.result;
          const context = getContext(this) as common.UIAbilityContext;
          const documentPicker = new picker.DocumentViewPicker(context);
          documentPicker.select({ maxSelectNumber: 1 })
            .then((uris: string[]) => { result.handleFileList(uris); })
            .catch(() => { result.handleFileList([]); });
          return true;
        })
        .onDownloadStart(() => {
          promptAction.showToast({ message: this.copy('downloadUnavailable') });
        })
        .width('100%')
        .height('100%')
      if (this.loadError.length > 0) {
        Column() {
          Column({ space: 20 }) {
            Text('知序').fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.foreground())
            Text(this.copy('errorTitle')).fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.foreground())
            Text(this.copy(this.loadError)).fontSize(16).lineHeight(26).fontColor(this.foreground())
              .textAlign(TextAlign.Center).width('100%')
            if (CLIENT_URL.length > 0) {
              Button(this.copy('reload')).fontSize(16).height(48).width('100%')
                .backgroundColor('#865338').fontColor('#FFFFFF').borderRadius(12)
                .onClick(() => { this.retry(); })
            }
            Text(this.copy('language')).fontSize(14).fontColor(this.foreground()).width('100%')
            Select([{ value: this.copy('system') },
              { value: SHELL_LANGUAGE_NAMES[0] }, { value: SHELL_LANGUAGE_NAMES[1] },
              { value: SHELL_LANGUAGE_NAMES[2] }, { value: SHELL_LANGUAGE_NAMES[3] },
              { value: SHELL_LANGUAGE_NAMES[4] }, { value: SHELL_LANGUAGE_NAMES[5] },
              { value: SHELL_LANGUAGE_NAMES[6] }, { value: SHELL_LANGUAGE_NAMES[7] },
              { value: SHELL_LANGUAGE_NAMES[8] }, { value: SHELL_LANGUAGE_NAMES[9] }])
              .selected(this.shellLanguage)
              .value(this.shellLanguage === 0 ? this.copy('system') : SHELL_LANGUAGE_NAMES[this.shellLanguage - 1])
              .width('100%').height(48).fontColor(this.foreground())
              .onSelect((index: number) => { this.shellLanguage = index; })
            Text(this.copy('theme')).fontSize(14).fontColor(this.foreground()).width('100%')
            Select([{ value: this.copy('system') }, { value: this.copy('light') }, { value: this.copy('dark') }])
              .selected(this.shellTheme)
              .value(this.copy(this.shellTheme === 0 ? 'system' : this.shellTheme === 1 ? 'light' : 'dark'))
              .width('100%').height(48).fontColor(this.foreground())
              .onSelect((index: number) => { this.shellTheme = index; })
          }
          .width('100%').constraintSize({ maxWidth: 480 })
        }
        .padding(32)
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.surface())
      }
    }
    .width('100%')
    .height('100%')
  }
}
