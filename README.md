# capacitor-zebra-bluetooth

A Capacitor plugin for communicating with Zebra thermal printers via Classic Bluetooth. Supports both iOS and Android platforms with full ZPL (Zebra Programming Language) command support.

## Features

- Discover paired Zebra Bluetooth printers
- Connect/disconnect to printers
- Send ZPL commands for label printing
- Get printer status (paper out, head open, etc.)
- Support for both iOS (ExternalAccessory framework) and Android (Bluetooth SPP)
- TypeScript support with full type definitions

## Supported Printers

This plugin works with Zebra mobile and desktop printers that support Bluetooth Classic (SPP profile), including:

- **Mobile Printers**: ZQ310, ZQ320, ZQ510, ZQ520, ZQ610, ZQ620, ZQ630
- **Desktop Printers**: ZD410, ZD420, ZD620, ZT230, ZT410, ZT420

## Installation

```bash
npm install capacitor-zebra-bluetooth
npx cap sync
```

## Platform Configuration

### iOS Configuration

#### 1. Add Bluetooth Protocol to Info.plist

Add the Zebra Bluetooth protocol string to your `ios/App/App/Info.plist`:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.zebra.rawport</string>
</array>
```

#### 2. Add Bluetooth Usage Description

Also add the Bluetooth usage description:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to Zebra printers for label printing.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to connect to Zebra printers for label printing.</string>
```

#### 3. Enable External Accessory Background Mode (Optional)

If you need to maintain printer connections in the background:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>external-accessory</string>
</array>
```

#### Important Notes for iOS

- **Printers must be paired via iOS Settings** before they can be discovered by the app
- The plugin uses Apple's ExternalAccessory framework, which requires MFi certification
- Zebra printers are MFi certified and use the `com.zebra.rawport` protocol

### Android Configuration

The plugin automatically adds required permissions to your AndroidManifest.xml:

```xml
<!-- Bluetooth permissions (Android 11 and below) -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />

<!-- Bluetooth permissions (Android 12+) -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Location permission (required for Bluetooth scanning on older versions) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

#### Important Notes for Android

- **Printers must be paired via Android Settings** before they can be discovered
- On Android 12+, the plugin requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` permissions
- On older versions, `ACCESS_FINE_LOCATION` is required for Bluetooth scanning

## Usage

### Import the Plugin

```typescript
import { CapacitorZebraBluetooth } from 'capacitor-zebra-bluetooth';
```

### Discover Printers

Discover all paired Zebra printers:

```typescript
const result = await CapacitorZebraBluetooth.discoverPrinters();
console.log('Found printers:', result.printers);

// Result structure:
// {
//   printers: [
//     {
//       friendlyName: "ZQ320-ABC123",
//       manufacturer: "Zebra Technologies",
//       modelName: "ZQ320",
//       connected: false
//     }
//   ]
// }
```

### Connect to a Printer

```typescript
const result = await CapacitorZebraBluetooth.connectToPrinter({
  friendlyName: 'ZQ320-ABC123'
});

if (result.success) {
  console.log('Connected successfully');
} else {
  console.error('Connection failed:', result.message);
}
```

### Check Connection Status

```typescript
const { connected } = await CapacitorZebraBluetooth.isConnected();
console.log('Is connected:', connected);
```

### Get Connected Printer

```typescript
const { printer } = await CapacitorZebraBluetooth.getConnectedPrinter();
if (printer) {
  console.log('Connected to:', printer.friendlyName);
}
```

### Send ZPL Commands

```typescript
// Simple label example
const zpl = `
^XA
^FO50,50^A0N,50,50^FDHello World^FS
^FO50,120^BY3^BCN,100,Y,N,N^FD12345678^FS
^XZ
`;

const result = await CapacitorZebraBluetooth.sendZPL({ zpl });

if (result.success) {
  console.log('Label printed successfully');
} else {
  console.error('Print failed:', result.message);
}
```

### Get Printer Status

```typescript
const { status } = await CapacitorZebraBluetooth.getPrinterStatus();

console.log('Printer status:', {
  connected: status.connected,
  ready: status.ready,
  printing: status.printing,
  paperOut: status.paperOut,
  headOpen: status.headOpen,
  message: status.message
});
```

### Disconnect

```typescript
await CapacitorZebraBluetooth.disconnect();
```

## Complete Example

Here's a complete example of a print service:

```typescript
import { CapacitorZebraBluetooth, type ZebraPrinter } from 'capacitor-zebra-bluetooth';

class PrintService {
  private selectedPrinter: ZebraPrinter | null = null;

  async discoverAndConnect(): Promise<boolean> {
    try {
      // Discover printers
      const { printers } = await CapacitorZebraBluetooth.discoverPrinters();

      if (printers.length === 0) {
        console.log('No printers found. Please pair a printer in device settings.');
        return false;
      }

      // Connect to first available printer
      this.selectedPrinter = printers[0];
      const result = await CapacitorZebraBluetooth.connectToPrinter({
        friendlyName: this.selectedPrinter.friendlyName
      });

      return result.success;
    } catch (error) {
      console.error('Error:', error);
      return false;
    }
  }

  async printLabel(text: string, barcode: string): Promise<boolean> {
    // Check connection
    const { connected } = await CapacitorZebraBluetooth.isConnected();
    if (!connected) {
      const success = await this.discoverAndConnect();
      if (!success) return false;
    }

    // Generate ZPL
    const zpl = `
^XA
^CI28
^FO50,50^A0N,40,40^FD${text}^FS
^FO50,100^BY2^BCN,80,Y,N,N^FD${barcode}^FS
^XZ
    `;

    // Send to printer
    const result = await CapacitorZebraBluetooth.sendZPL({ zpl });
    return result.success;
  }

  async checkPrinterReady(): Promise<boolean> {
    const { status } = await CapacitorZebraBluetooth.getPrinterStatus();

    if (status.paperOut) {
      console.warn('Printer is out of paper');
      return false;
    }

    if (status.headOpen) {
      console.warn('Printer head is open');
      return false;
    }

    return status.ready;
  }
}
```

## ZPL Quick Reference

Here are some common ZPL commands:

| Command | Description | Example |
|---------|-------------|---------|
| `^XA` | Start label format | `^XA` |
| `^XZ` | End label format | `^XZ` |
| `^FO` | Field origin (x,y position) | `^FO50,100` |
| `^FD` | Field data | `^FDHello^FS` |
| `^FS` | Field separator (end field) | `^FS` |
| `^A0N` | Scalable font | `^A0N,50,50` |
| `^BC` | Code 128 barcode | `^BCN,100,Y,N,N` |
| `^BQ` | QR Code | `^BQN,2,5` |
| `^BY` | Bar code field default | `^BY3` |
| `^GB` | Graphic box (line/rectangle) | `^GB200,3,3^FS` |
| `^CI28` | UTF-8 character set | `^CI28` |
| `^LL` | Label length | `^LL400` |
| `^PW` | Print width | `^PW400` |

### Sample Labels

#### Simple Text Label

```zpl
^XA
^CI28
^FO50,50^A0N,30,30^FDProduct: Widget^FS
^FO50,90^A0N,30,30^FDPrice: $9.99^FS
^XZ
```

#### Barcode Label

```zpl
^XA
^FO50,50^A0N,25,25^FDSKU: ABC123^FS
^FO50,80^BY2^BCN,80,Y,N,N^FDABC123^FS
^XZ
```

#### QR Code Label

```zpl
^XA
^FO50,50^BQN,2,5^FDQA,https://example.com^FS
^XZ
```

#### Receipt-style Label

```zpl
^XA
^CI28
^PW400
^LL800

^FO50,30^A0N,30,30^FDCompany Name^FS
^FO50,70^GB300,2,2^FS

^FO50,90^A0N,20,20^FDItem 1^FS
^FO300,90^A0N,20,20^FD$10.00^FS

^FO50,120^A0N,20,20^FDItem 2^FS
^FO300,120^A0N,20,20^FD$15.00^FS

^FO50,160^GB300,2,2^FS
^FO50,180^A0N,25,25^FDTotal: $25.00^FS

^XZ
```

## API Reference

### discoverPrinters()

```typescript
discoverPrinters(): Promise<{ printers: ZebraPrinter[] }>
```

Discover available Zebra printers via Classic Bluetooth. On iOS, only previously paired printers will be returned.

### connectToPrinter(options)

```typescript
connectToPrinter(options: { friendlyName: string }): Promise<{ success: boolean; message?: string }>
```

Connect to a Zebra printer by its friendly name.

### disconnect()

```typescript
disconnect(): Promise<{ success: boolean }>
```

Disconnect from the currently connected printer.

### isConnected()

```typescript
isConnected(): Promise<{ connected: boolean }>
```

Check if a printer is currently connected.

### getConnectedPrinter()

```typescript
getConnectedPrinter(): Promise<{ printer: ZebraPrinter | null }>
```

Get the currently connected printer information.

### sendZPL(options)

```typescript
sendZPL(options: { zpl: string }): Promise<{ success: boolean; message?: string }>
```

Send ZPL commands to the connected printer.

### getPrinterStatus()

```typescript
getPrinterStatus(): Promise<{ status: PrinterStatus }>
```

Get the current printer status including paper and head status.

## Type Definitions

### ZebraPrinter

```typescript
interface ZebraPrinter {
  friendlyName: string;
  manufacturer?: string;
  modelName?: string;
  serialNumber?: string;
  connected: boolean;
}
```

### PrinterStatus

```typescript
interface PrinterStatus {
  connected: boolean;
  ready: boolean;
  printing: boolean;
  paperOut: boolean;
  headOpen: boolean;
  message?: string;
}
```

## Troubleshooting

### Printer not discovered

1. **Ensure the printer is paired** in your device's Bluetooth settings
2. **Restart the printer** and your device
3. **Check battery level** on mobile printers
4. On Android, ensure **location services are enabled** (required for Bluetooth scanning)

### Connection fails

1. **Unpair and re-pair** the printer in device settings
2. **Restart the printer** - hold power button until it beeps twice
3. Check that no other app is connected to the printer
4. Verify printer is in **Bluetooth Classic mode**, not BLE-only

### Printing issues

1. **Check paper/labels** are loaded correctly
2. **Calibrate the printer** using the feed button (hold for 2 seconds)
3. **Verify ZPL syntax** - use Zebra's labelary.com for testing
4. Ensure `^XA` and `^XZ` tags are present

### iOS-specific issues

- Printer must appear in **Settings > Bluetooth > My Devices**
- Check `UISupportedExternalAccessoryProtocols` includes `com.zebra.rawport`
- Some older Zebra printers may not be MFi certified

### Android-specific issues

- On Android 12+, grant both **Nearby devices** and **Location** permissions
- Ensure the app has permission to scan and connect via Bluetooth

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Development

```bash
# Install dependencies
npm install

# Build the plugin
npm run build

# Watch for changes
npm run watch

# Run linter
npm run lint

# Format code
npm run fmt
```

## License

MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Zebra Technologies for their printer SDKs and documentation
- Capacitor team for the excellent plugin architecture
- Contributors and users who provide feedback and improvements

## Support

- [GitHub Issues](https://github.com/huqe21/capacitor-zebra-bluetooth/issues)
- [Zebra Developer Portal](https://developer.zebra.com/)
- [ZPL Programming Guide](https://www.zebra.com/content/dam/zebra/manuals/printers/common/programming/zpl-zbi2-pm-en.pdf)
