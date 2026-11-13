// Jobs: localized shell recovery UI; the embedded client owns normal page settings.
export const SHELL_LANGUAGES: string[] = ["zh","zh-Hant","bo","en","ja","fr","es","de","ru","ko"];
export const SHELL_LANGUAGE_NAMES: string[] = ["简体中文","繁體中文","བོད་ཡིག","English","日本語","Français","Español","Deutsch","Русский","한국어"];
const COPY: Map<string, string[]> = new Map<string, string[]>([
  ["reload", ["重新加载","重新載入","ཡང་བསྐྱར་འཇུག","Reload","再読み込み","Recharger","Recargar","Neu laden","Обновить","새로고침"]],
  ["language", ["语言","語言","སྐད་ཡིག","Language","言語","Langue","Idioma","Sprache","Язык","언어"]],
  ["theme", ["主题","主題","བཟོ་ལྟ།","Theme","テーマ","Apparence","Tema","Design","Тема","테마"]],
  ["system", ["跟随系统","跟隨系統","མ་ལག་ལྟར།","System","システム","Système","Sistema","System","Системная","시스템"]],
  ["light", ["白天","白天","ཉིན་མོ།","Light","ライト","Clair","Claro","Hell","Светлая","라이트"]],
  ["dark", ["黑夜","黑夜","མཚན་མོ།","Dark","ダーク","Sombre","Oscuro","Dunkel","Тёмная","다크"]],
  ["errorTitle", ["连接服务后继续","連線服務後繼續","ཞབས་ཞུར་འབྲེལ་ནས་མུ་མཐུད།","Connect to continue","接続して続行","Connectez-vous pour continuer","Conecta para continuar","Verbinden und fortfahren","Подключитесь для продолжения","연결하여 계속"]],
  ["unconfigured", ["尚未配置服务地址，请联系管理员完成连接设置。","尚未設定服務位址，請聯絡管理員完成連線設定。","ཞབས་ཞུའི་ཁ་བྱང་མ་བཀོད། དོ་དམ་པར་འབྲེལ་ནས་འབྲེལ་མཐུད་སྒྲིག་འགོད་བྱོས།","The service address is not configured. Contact your administrator to finish connection setup.","接続先が未設定です。管理者に接続設定を依頼してください。","L’adresse du service n’est pas configurée. Contactez votre administrateur.","La dirección del servicio no está configurada. Contacta con el administrador.","Die Dienstadresse ist nicht eingerichtet. Wenden Sie sich an die Administration.","Адрес сервиса не настроен. Обратитесь к администратору.","서비스 주소가 설정되지 않았습니다. 관리자에게 연결 설정을 요청하세요."]],
  ["network", ["连接失败，请检查网络与HTTPS证书后重新加载。","連線失敗，請檢查網路與HTTPS憑證後重新載入。","འབྲེལ་མཐུད་མ་ཐུབ། དྲ་རྒྱ་དང་HTTPS དཔང་ཡིག་ཞིབ་བཤེར་རྗེས་བསྐྱར་འཇུག་བྱོས།","Connection failed. Check your network and HTTPS certificate, then reload.","接続できません。ネットワークとHTTPS証明書を確認して再読み込みしてください。","Connexion impossible. Vérifiez le réseau et le certificat HTTPS, puis rechargez.","Error de conexión. Comprueba la red y el certificado HTTPS y recarga.","Verbindung fehlgeschlagen. Netzwerk und HTTPS-Zertifikat prüfen und neu laden.","Не удалось подключиться. Проверьте сеть и сертификат HTTPS, затем обновите.","연결하지 못했습니다. 네트워크와 HTTPS 인증서를 확인한 후 다시 불러오세요."]],
  ["unavailable", ["服务暂时不可用，请稍后重新加载。","服務暫時無法使用，請稍後重新載入。","ཞབས་ཞུ་གནས་སྐབས་སྤྱོད་མི་ཐུབ། ཅུང་ཙམ་རྗེས་བསྐྱར་འཇུག་བྱོས།","The service is temporarily unavailable. Reload in a moment.","サービスを一時的に利用できません。しばらくして再読み込みしてください。","Service temporairement indisponible. Réessayez dans un instant.","El servicio no está disponible temporalmente. Recarga en un momento.","Dienst vorübergehend nicht verfügbar. Gleich erneut laden.","Сервис временно недоступен. Обновите немного позже.","서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 불러오세요."]],
  ["downloadUnavailable", ["当前设备暂不支持保存原件，请在iOS、Android或桌面端下载。","目前裝置暫不支援儲存原件，請在iOS、Android或桌面端下載。","ཆས་འདིར་མ་ཡིག་ཉར་མི་ཐུབ། iOS དང་Android ཡང་ན་གློག་ཀླད་ནས་ཕབ་ལེན་བྱོས།","Saving originals is not supported on this device yet. Download on iOS, Android or desktop.","この端末では原本を保存できません。iOS・Android・デスクトップでダウンロードしてください。","L’enregistrement des originaux n’est pas encore pris en charge ici. Téléchargez sur iOS, Android ou ordinateur.","Este dispositivo aún no permite guardar originales. Descarga desde iOS, Android o escritorio.","Originale können hier noch nicht gespeichert werden. Über iOS, Android oder Desktop herunterladen.","На этом устройстве сохранение оригиналов пока недоступно. Скачайте на iOS, Android или ПК.","이 기기는 아직 원본 저장을 지원하지 않습니다. iOS, Android 또는 PC에서 다운로드하세요."]]
]);

export function shellText(key: string, locale: string): string {
  const index = Math.max(0, SHELL_LANGUAGES.indexOf(locale));
  const values = COPY.get(key);
  return values ? values[index] : key;
}
