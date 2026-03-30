// Global type definitions for client-side
interface Window {
  __STATBUS_CONFIG__: import("@/lib/statbus-config").StatbusConfig;
  __NEXT_DATA__: {
    props: {
      deploymentSlotCode: string;
      [key: string]: any;
    };
    [key: string]: any;
  };
}
