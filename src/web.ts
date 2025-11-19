import { WebPlugin } from '@capacitor/core';

import type { CapacitorZebraBluetoothPlugin, ZebraPrinter, PrinterStatus } from './definitions';

export class CapacitorZebraBluetoothWeb extends WebPlugin implements CapacitorZebraBluetoothPlugin {
  async discoverPrinters(): Promise<{ printers: ZebraPrinter[] }> {
    console.warn('CapacitorZebraBluetooth: Bluetooth printing is not available on web platform');
    return { printers: [] };
  }

  async connectToPrinter(_options: { friendlyName: string }): Promise<{ success: boolean; message?: string }> {
    console.warn('CapacitorZebraBluetooth: Bluetooth printing is not available on web platform');
    return { success: false, message: 'Not supported on web platform' };
  }

  async disconnect(): Promise<{ success: boolean }> {
    console.warn('CapacitorZebraBluetooth: Bluetooth printing is not available on web platform');
    return { success: false };
  }

  async isConnected(): Promise<{ connected: boolean }> {
    return { connected: false };
  }

  async getConnectedPrinter(): Promise<{ printer: ZebraPrinter | null }> {
    return { printer: null };
  }

  async sendZPL(_options: { zpl: string }): Promise<{ success: boolean; message?: string }> {
    console.warn('CapacitorZebraBluetooth: Bluetooth printing is not available on web platform');
    console.log('ZPL Command (Web Preview):\n', _options.zpl);
    return { success: false, message: 'Not supported on web platform' };
  }

  async getPrinterStatus(): Promise<{ status: PrinterStatus }> {
    return {
      status: {
        connected: false,
        ready: false,
        printing: false,
        paperOut: false,
        headOpen: false,
        message: 'Web platform not supported'
      }
    };
  }
}
