package ukjin.sempan;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;

/** 웹 버전(assets/index.html)을 그대로 띄우는 화면 */
public class MainActivity extends Activity {
    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        // 저장 슬롯은 localStorage에 들어가요
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setTextZoom(100);
        // 소리는 첫 터치 뒤에 켜져요 (웹과 같은 방식)
        s.setMediaPlaybackRequiresUserGesture(true);
        web.setOverScrollMode(WebView.OVER_SCROLL_NEVER);
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    /** 뒤로 가기: 열린 시트를 닫거나 메인 화면으로 가고, 메인 화면이면 앱을 닫아요 */
    @Override
    public void onBackPressed() {
        web.evaluateJavascript("window.sempanBack ? sempanBack() : false", handled -> {
            if (!"true".equals(handled)) finish();
        });
    }

    @Override
    protected void onPause() {
        // 백그라운드에서는 배경음과 효과음을 멈춰요
        web.evaluateJavascript("window.sempanPause && sempanPause()", null);
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
        web.evaluateJavascript("window.sempanResume && sempanResume()", null);
    }

    @Override
    protected void onDestroy() {
        web.destroy();
        super.onDestroy();
    }
}
