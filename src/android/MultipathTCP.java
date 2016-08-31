package com.rosepoint;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;

import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkRequest;
import android.provider.Settings;
import android.text.TextUtils;
import android.util.Log;
import android.net.NetworkInfo.State;
import android.net.NetworkCapabilities;

import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.net.ProtocolException;
import java.net.URL;
import java.net.URLConnection;
import java.net.HttpURLConnection;
import java.util.List;
import java.util.Map;

/**
 * This class echoes a string called from JavaScript.
 */
public class MultipathTCP extends CordovaPlugin {
    String url, method;
    CallbackContext callbackContext;
    CallbackContext progressContext;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if (action.equals("request")) {
            this.method = args.getString(0);
            this.url = args.getString(1);
            this.callbackContext = callbackContext;
            request();
            return true;
        } else if (action.equals("onRequestProgress")){
            this.progressContext = callbackContext;
            return true;
        }
        return false;
    }

    private void request() {
        final Activity activity = this.cordova.getActivity();
        Context context = activity.getApplicationContext();
        if (context.checkSelfPermission(Manifest.permission.CHANGE_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) {
            establishConnection(method, url, callbackContext);
            return;
            //cordova.getActivity().startActivity(new Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS));
            //return;
        } else {
            establishConnection(method, url, callbackContext);
        }
    }

    public void onRequestPermissionResult(int requestCode, String[] permissions, int[] grantResults){
        establishConnection(this.method, this.url, this.callbackContext);
    }

    private void establishConnection(final String method, final String url, final CallbackContext callbackContext){
        Context context = cordova.getActivity().getApplicationContext();

        ConnectivityManager connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkRequest.Builder builder = new NetworkRequest.Builder();
        builder.addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR);
        ConnectivityManager.NetworkCallback networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                try {
                    makeHTTPRequest(method, url, network, callbackContext);
                } catch (IOException e) {
                    callbackContext.error("error establishing HTTP connection");
                }
            }
        };
        connectivityManager.requestNetwork(builder.build(), networkCallback);
    }

    private void makeHTTPRequest(String method, String urlString, Network network, CallbackContext callbackContext) throws IOException {
        URL url;
        try {
            url = new URL(urlString);
        } catch (MalformedURLException e){
            callbackContext.error("bad url provided");
            return;
        }

        HttpURLConnection connection;
        InputStream inputStream;
        int responseCode;
        int contentLength = 0;
        Map<String,List<String>> headers;

        connection = (HttpURLConnection) network.openConnection(url);
        connection.setRequestMethod(method);
        connection.setInstanceFollowRedirects(true);
        inputStream = connection.getInputStream();
        responseCode = connection.getResponseCode();
        headers = connection.getHeaderFields();
        List<String> contentLengthList = headers.get("Content-Length");
        if (contentLengthList != null) {
            contentLength = Integer.parseInt(contentLengthList.get(0));
        }

        //connection went through. get code, headers, and body
        int bytesRead, lastNotificationSize = 0, totalBytesRead = 0, chunkSize = 4096;
        byte[]buffer = new byte[contentLength];
        while((bytesRead = inputStream.read(buffer,  totalBytesRead,
                Math.min(contentLength - totalBytesRead, chunkSize))) != -1) {
            totalBytesRead += bytesRead;
            if(totalBytesRead - lastNotificationSize > 1000000 && progressContext != null) {
                lastNotificationSize = totalBytesRead;
                float progress = (float)totalBytesRead/contentLength;
                PluginResult progressResult = new PluginResult(PluginResult.Status.OK, progress);
                progressResult.setKeepCallback(true);
                progressContext.sendPluginResult(progressResult);
            }
            Log.d(TAG, "bytes read: " + totalBytesRead);
        }
        inputStream.close();

        List<PluginResult> results = new java.util.ArrayList<PluginResult>();
        results.add(new PluginResult(PluginResult.Status.OK, connection.getResponseCode()));
        try {
            results.add(new PluginResult(PluginResult.Status.OK, headersToJSON(headers)));
        } catch (JSONException e) {
            throw new IOException("failed to parse headers");
        }
        results.add(new PluginResult(PluginResult.Status.OK, buffer));

        PluginResult requestResult = new PluginResult(PluginResult.Status.OK, results);
        callbackContext.sendPluginResult(requestResult);
    }

    private JSONObject headersToJSON(Map<String, List<String>>headers) throws JSONException{
        JSONObject obj = new JSONObject();
        for (Map.Entry<String, List<String>> entry : headers.entrySet()){
            String key;
            if ((key = entry.getKey()) != null){
                obj.put(key, entry.getValue().get(0));
            }
        }
        return obj;
    }

    private static final String TAG = "MultipathTCP";

}
