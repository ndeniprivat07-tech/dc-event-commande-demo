package ci.dcevent.commande;

import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;
import androidx.webkit.WebViewAssetLoader;

/**
 * DC EVENT COMMANDE — enveloppe Android.
 *
 * L'application web (index.html) est embarquée dans l'APK et servie par un
 * WebViewAssetLoader sous une origine https stable : localStorage fonctionne
 * de façon fiable et aucun réseau n'est nécessaire.
 *
 * La WebView n'implémente pas WebAuthn : le déverrouillage par empreinte
 * passe donc par un pont vers BiometricPrompt. C'est le système Android qui
 * affiche la boîte de dialogue et lit le capteur — ni cette application ni
 * la page web ne voient jamais l'empreinte elle-même.
 */
public class MainActivity extends AppCompatActivity {

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

        vue.addJavascriptInterface(new PontBiometrie(), "AndroidBio");

        vue.loadUrl("https://appassets.androidplatform.net/assets/index.html");
        setContentView(vue);
    }

    /** Renvoie le resultat a la page web, sur le fil principal. */
    private void repondre(final boolean ok, final String message) {
        runOnUiThread(new Runnable() {
            @Override public void run() {
                String js = "window.__bioReponse && window.__bioReponse(" + ok + ",'"
                          + (message == null ? "" : message.replace("'", " ")) + "')";
                vue.evaluateJavascript(js, null);
            }
        });
    }

    /** Pont expose a la page sous le nom AndroidBio. */
    private class PontBiometrie {

        /** Vrai seulement si le materiel existe ET qu'une empreinte est enregistree. */
        @JavascriptInterface
        public boolean disponible() {
            int etat = BiometricManager.from(MainActivity.this)
                    .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK
                                   | BiometricManager.Authenticators.DEVICE_CREDENTIAL);
            return etat == BiometricManager.BIOMETRIC_SUCCESS;
        }

        /** Ouvre la boite de dialogue systeme ; la reponse arrive par __bioReponse. */
        @JavascriptInterface
        public void demander(final String titre, final String sousTitre) {
            runOnUiThread(new Runnable() {
                @Override public void run() { ouvrirDialogue(titre, sousTitre); }
            });
        }
    }

    private void ouvrirDialogue(String titre, String sousTitre) {
        BiometricPrompt prompt = new BiometricPrompt(this,
                ContextCompat.getMainExecutor(this),
                new BiometricPrompt.AuthenticationCallback() {

            @Override
            public void onAuthenticationSucceeded(@NonNull BiometricPrompt.AuthenticationResult r) {
                repondre(true, "");
            }

            @Override
            public void onAuthenticationError(int code, @NonNull CharSequence texte) {
                // Inclut l'annulation par l'utilisateur : la page repropose le mot de passe.
                repondre(false, texte.toString());
            }

            @Override
            public void onAuthenticationFailed() {
                // Doigt non reconnu : le systeme laisse reessayer, on ne repond pas encore.
            }
        });

        BiometricPrompt.PromptInfo info = new BiometricPrompt.PromptInfo.Builder()
                .setTitle(titre == null || titre.isEmpty() ? "DC EVENT COMMANDE" : titre)
                .setSubtitle(sousTitre == null ? "" : sousTitre)
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK
                                        | BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                .build();

        prompt.authenticate(info);
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
