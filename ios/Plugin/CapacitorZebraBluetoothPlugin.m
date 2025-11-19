#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro
CAP_PLUGIN(CapacitorZebraBluetoothPlugin, "CapacitorZebraBluetooth",
           CAP_PLUGIN_METHOD(discoverPrinters, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(connectToPrinter, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(disconnect, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(isConnected, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getConnectedPrinter, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(sendZPL, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getPrinterStatus, CAPPluginReturnPromise);
)
