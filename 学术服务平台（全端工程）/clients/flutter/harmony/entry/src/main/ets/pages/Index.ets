import { webview } from '@kit.ArkWeb';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { CLIENT_ORIGIN, CLIENT_URL } from '../config/Endpoint';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private loadError: string = '';
  private controllerAttached: boolean = false;

  aboutToAppear(): void {
    if (CLIENT_URL.length === 0) {
      this.loadError = '尚未配置服务地址。请先运行 prepare_harmony.py 指定 HTTPS API，再使用 DevEco 打包。';
    }
  }

  private retry(): void {
    if (!this.controllerAttached || CLIENT_URL.length === 0) {
      return;
    }
    this.loadError = '';
    this.controller.loadUrl(CLIENT_URL);
  }

  build() {
    Stack() {
      Web({ src: CLIENT_URL.length > 0 ? CLIENT_URL : 'about:blank', controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .mixedMode(MixedMode.None)
        .onControllerAttached(() => { this.controllerAttached = true; })
        .onLoadIntercept((event) => {
          if (!event) { return true; }
          const target = event.data.getRequestUrl();
          if (target === 'about:blank' && CLIENT_URL.length === 0) { return false; }
          return CLIENT_ORIGIN.length === 0 || !target.startsWith(CLIENT_ORIGIN + '/');
        })
        .onErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            this.loadError = '无法连接服务。检查网络与 HTTPS 证书后重试；首次启动需要联网。';
          }
        })
        .onHttpErrorReceive((event) => {
          if (event && event.request.isMainFrame()) {
            this.loadError = '服务暂时不可用，请稍后重试。';
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
          promptAction.showToast({ message: '当前鸿蒙宿主尚不支持保存原件，请在 iOS、Android 或桌面端授权下载。' });
        })
        .width('100%')
        .height('100%')
      if (this.loadError.length > 0) {
        Column({ space: 20 }) {
          Text('知序').fontSize(28).fontWeight(FontWeight.Bold)
          Text(this.loadError).fontSize(16).textAlign(TextAlign.Center)
          if (CLIENT_URL.length > 0) {
            Button('重新加载').onClick(() => { this.retry(); })
          }
        }
        .padding(32)
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F6F7F3')
      }
    }
    .width('100%')
    .height('100%')
  }
}
