package ci.dcevent.commande;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.webkit.WebViewAssetLoader;

/**
 * DC EVENT COMMANDE — enveloppe Android.
 *
 * L'application web (index.html) est embarquée dans l'APK et servie par un
 * WebViewAssetLoader sous une origine https stable. Deux conséquences :
 *  - localStorage fonctionne de façon fiable (les données survivent aux
 *    redémarrages du téléphone) ;
 *  - aucun réseau n'est nécessaire, jamais.
 */
public class MainActivity extends Activity {

    private WebView vue;

    @Override
    protected void onCreate(Bundle etat) {
        super.onCreate(etat);

        vue = new WebView(this);
        WebSettings p = vue.getSettings();
        p.setJavaScriptEnabled(true);
        p.setDomStorageEnabled(true);   // indispensable : les donnees vivent dans localStorage

        final WebViewAssetLoader chargeur = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();

        vue.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                return chargeur.shouldInterceptRequest(r.getUrl());
            }
        });

        // Sans WebChromeClient, les boites alert/confirm/prompt de l'application
        // (motifs de validation, confirmations) seraient silencieusement ignorees.
        vue.setWebChromeClient(new WebChromeClient());

        vue.loadUrl("https://appassets.androidplatform.net/assets/index.html");
        setContentView(vue);
    }

    @Override
    public void onBackPressed() {
        if (vue != null && vue.canGoBack()) {
            vue.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
