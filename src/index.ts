import { registerPlugin } from '@capacitor/core';

import type { CapacitorZebraBluetoothPlugin } from './definitions';

const CapacitorZebraBluetooth = registerPlugin<CapacitorZebraBluetoothPlugin>(
  'CapacitorZebraBluetooth',
  {
    web: () => import('./web').then(m => new m.CapacitorZebraBluetoothWeb()),
  },
);

export * from './definitions';
export { CapacitorZebraBluetooth };
