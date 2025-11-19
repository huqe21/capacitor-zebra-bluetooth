package com.capacitorzebrabluetooth;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import androidx.core.app.ActivityCompat;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Set;
import java.util.UUID;

@CapacitorPlugin(
    name = "CapacitorZebraBluetooth",
    permissions = {
        @Permission(
            strings = { Manifest.permission.BLUETOOTH },
            alias = "bluetooth"
        ),
        @Permission(
            strings = { Manifest.permission.BLUETOOTH_ADMIN },
            alias = "bluetoothAdmin"
        ),
        @Permission(
            strings = { Manifest.permission.BLUETOOTH_SCAN },
            alias = "bluetoothScan"
        ),
        @Permission(
            strings = { Manifest.permission.BLUETOOTH_CONNECT },
            alias = "bluetoothConnect"
        ),
        @Permission(
            strings = { Manifest.permission.ACCESS_FINE_LOCATION },
            alias = "location"
        )
    }
)
public class CapacitorZebraBluetoothPlugin extends Plugin {

    private static final String TAG = "CapacitorZebraBT";
    private static final UUID SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");

    private BluetoothAdapter bluetoothAdapter;
    private BluetoothSocket connectedSocket;
    private BluetoothDevice connectedDevice;
    private OutputStream outputStream;
    private InputStream inputStream;

    @Override
    public void load() {
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
    }

    @PluginMethod
    public void discoverPrinters(PluginCall call) {
        if (bluetoothAdapter == null) {
            call.reject("Bluetooth is not available on this device");
            return;
        }

        if (!hasRequiredPermissions()) {
            requestAllPermissions(call, "discoverPrintersCallback");
            return;
        }

        try {
            JSArray printers = new JSArray();
            Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();

            if (pairedDevices != null) {
                for (BluetoothDevice device : pairedDevices) {
                    String deviceName = device.getName();
                    // Filter for Zebra printers (names typically start with "ZEB" or contain "Zebra")
                    if (deviceName != null && (deviceName.toUpperCase().startsWith("ZEB") ||
                        deviceName.toUpperCase().contains("ZEBRA") ||
                        deviceName.toUpperCase().contains("ZQ") ||
                        deviceName.toUpperCase().contains("ZD") ||
                        deviceName.toUpperCase().contains("ZT"))) {

                        JSObject printer = new JSObject();
                        printer.put("friendlyName", deviceName);
                        printer.put("manufacturer", "Zebra Technologies");
                        printer.put("modelName", extractModelName(deviceName));
                        printer.put("connected", device.equals(connectedDevice));
                        printers.put(printer);
                    }
                }
            }

            JSObject result = new JSObject();
            result.put("printers", printers);
            call.resolve(result);

        } catch (SecurityException e) {
            call.reject("Bluetooth permission denied: " + e.getMessage());
        } catch (Exception e) {
            call.reject("Error discovering printers: " + e.getMessage());
        }
    }

    @PermissionCallback
    private void discoverPrintersCallback(PluginCall call) {
        if (hasRequiredPermissions()) {
            discoverPrinters(call);
        } else {
            call.reject("Bluetooth permissions are required");
        }
    }

    @PluginMethod
    public void connectToPrinter(PluginCall call) {
        String friendlyName = call.getString("friendlyName");
        if (friendlyName == null || friendlyName.isEmpty()) {
            call.reject("Printer friendly name is required");
            return;
        }

        if (!hasRequiredPermissions()) {
            requestAllPermissions(call, "connectCallback");
            return;
        }

        try {
            // Disconnect existing connection if any
            disconnect(null);

            Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
            BluetoothDevice targetDevice = null;

            for (BluetoothDevice device : pairedDevices) {
                if (friendlyName.equals(device.getName())) {
                    targetDevice = device;
                    break;
                }
            }

            if (targetDevice == null) {
                JSObject result = new JSObject();
                result.put("success", false);
                result.put("message", "Printer not found: " + friendlyName);
                call.resolve(result);
                return;
            }

            // Cancel discovery to improve connection speed
            bluetoothAdapter.cancelDiscovery();

            // Create socket and connect
            connectedSocket = targetDevice.createRfcommSocketToServiceRecord(SPP_UUID);
            connectedSocket.connect();

            outputStream = connectedSocket.getOutputStream();
            inputStream = connectedSocket.getInputStream();
            connectedDevice = targetDevice;

            JSObject result = new JSObject();
            result.put("success", true);
            result.put("message", "Connected to " + friendlyName);
            call.resolve(result);

        } catch (SecurityException e) {
            call.reject("Bluetooth permission denied: " + e.getMessage());
        } catch (IOException e) {
            cleanup();
            JSObject result = new JSObject();
            result.put("success", false);
            result.put("message", "Connection failed: " + e.getMessage());
            call.resolve(result);
        } catch (Exception e) {
            cleanup();
            call.reject("Error connecting to printer: " + e.getMessage());
        }
    }

    @PermissionCallback
    private void connectCallback(PluginCall call) {
        if (hasRequiredPermissions()) {
            connectToPrinter(call);
        } else {
            call.reject("Bluetooth permissions are required");
        }
    }

    @PluginMethod
    public void disconnect(PluginCall call) {
        cleanup();

        if (call != null) {
            JSObject result = new JSObject();
            result.put("success", true);
            call.resolve(result);
        }
    }

    @PluginMethod
    public void isConnected(PluginCall call) {
        boolean connected = connectedSocket != null && connectedSocket.isConnected();

        JSObject result = new JSObject();
        result.put("connected", connected);
        call.resolve(result);
    }

    @PluginMethod
    public void getConnectedPrinter(PluginCall call) {
        JSObject result = new JSObject();

        if (connectedDevice != null && connectedSocket != null && connectedSocket.isConnected()) {
            try {
                JSObject printer = new JSObject();
                printer.put("friendlyName", connectedDevice.getName());
                printer.put("manufacturer", "Zebra Technologies");
                printer.put("modelName", extractModelName(connectedDevice.getName()));
                printer.put("connected", true);
                result.put("printer", printer);
            } catch (SecurityException e) {
                result.put("printer", JSObject.NULL);
            }
        } else {
            result.put("printer", JSObject.NULL);
        }

        call.resolve(result);
    }

    @PluginMethod
    public void sendZPL(PluginCall call) {
        String zpl = call.getString("zpl");
        if (zpl == null || zpl.isEmpty()) {
            call.reject("ZPL data is required");
            return;
        }

        if (outputStream == null || connectedSocket == null || !connectedSocket.isConnected()) {
            JSObject result = new JSObject();
            result.put("success", false);
            result.put("message", "Not connected to a printer");
            call.resolve(result);
            return;
        }

        try {
            byte[] data = zpl.getBytes("UTF-8");
            outputStream.write(data);
            outputStream.flush();

            JSObject result = new JSObject();
            result.put("success", true);
            result.put("message", "ZPL sent successfully");
            call.resolve(result);

        } catch (IOException e) {
            JSObject result = new JSObject();
            result.put("success", false);
            result.put("message", "Failed to send ZPL: " + e.getMessage());
            call.resolve(result);
        }
    }

    @PluginMethod
    public void getPrinterStatus(PluginCall call) {
        JSObject status = new JSObject();

        boolean connected = connectedSocket != null && connectedSocket.isConnected();
        status.put("connected", connected);
        status.put("ready", connected);
        status.put("printing", false);
        status.put("paperOut", false);
        status.put("headOpen", false);

        if (connected) {
            try {
                // Send SGD command to get printer status
                String statusCommand = "~HS";
                outputStream.write(statusCommand.getBytes("UTF-8"));
                outputStream.flush();

                // Wait a bit for response
                Thread.sleep(100);

                if (inputStream.available() > 0) {
                    byte[] buffer = new byte[1024];
                    int bytesRead = inputStream.read(buffer);
                    String response = new String(buffer, 0, bytesRead, "UTF-8");
                    status.put("message", response);

                    // Parse basic status from response
                    if (response.contains("PAPER OUT")) {
                        status.put("paperOut", true);
                        status.put("ready", false);
                    }
                    if (response.contains("HEAD OPEN")) {
                        status.put("headOpen", true);
                        status.put("ready", false);
                    }
                }
            } catch (Exception e) {
                status.put("message", "Could not retrieve detailed status");
            }
        }

        JSObject result = new JSObject();
        result.put("status", status);
        call.resolve(result);
    }

    private boolean hasRequiredPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                   ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED;
        } else {
            return ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
                   ActivityCompat.checkSelfPermission(getContext(), Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
        }
    }

    private void requestAllPermissions(PluginCall call, String callbackName) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissionForAliases(new String[]{"bluetoothConnect", "bluetoothScan"}, call, callbackName);
        } else {
            requestPermissionForAliases(new String[]{"bluetooth", "location"}, call, callbackName);
        }
    }

    private String extractModelName(String deviceName) {
        if (deviceName == null) return null;

        // Common Zebra model patterns
        String upper = deviceName.toUpperCase();
        if (upper.contains("ZQ320")) return "ZQ320";
        if (upper.contains("ZQ310")) return "ZQ310";
        if (upper.contains("ZQ520")) return "ZQ520";
        if (upper.contains("ZQ510")) return "ZQ510";
        if (upper.contains("ZQ630")) return "ZQ630";
        if (upper.contains("ZQ620")) return "ZQ620";
        if (upper.contains("ZD410")) return "ZD410";
        if (upper.contains("ZD420")) return "ZD420";
        if (upper.contains("ZD620")) return "ZD620";
        if (upper.contains("ZT230")) return "ZT230";
        if (upper.contains("ZT410")) return "ZT410";
        if (upper.contains("ZT420")) return "ZT420";

        return null;
    }

    private void cleanup() {
        try {
            if (outputStream != null) {
                outputStream.close();
                outputStream = null;
            }
            if (inputStream != null) {
                inputStream.close();
                inputStream = null;
            }
            if (connectedSocket != null) {
                connectedSocket.close();
                connectedSocket = null;
            }
            connectedDevice = null;
        } catch (IOException e) {
            Log.e(TAG, "Error during cleanup: " + e.getMessage());
        }
    }
}
