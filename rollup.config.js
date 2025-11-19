export default {
  input: 'dist/esm/index.js',
  output: [
    {
      file: 'dist/plugin.cjs.js',
      format: 'cjs',
      sourcemap: true,
      inlineDynamicImports: true,
    },
    {
      file: 'dist/plugin.js',
      format: 'iife',
      name: 'capacitorCapacitorZebraBluetooth',
      globals: {
        '@capacitor/core': 'capacitorExports',
      },
      sourcemap: true,
      inlineDynamicImports: true,
    },
  ],
  external: ['@capacitor/core'],
};
