/**
 * ZITLAS App Configuration
 * Set IS_DEMO_MODE = true only in staging/preview environments.
 * Production deployments must keep this false.
 */

var IS_DEMO_MODE = false;

/* Feature flags */
var ZITLAS_CONFIG = {
  IS_DEMO_MODE:        IS_DEMO_MODE,
  PAYMENT_ENABLED:     false,   /* flip to true when payment gateway is wired */
  HEALTH_CONNECT:      true,    /* attempt Health Connect on supported devices */
  CHAT_ENABLED:        false,   /* real-time chat backend not yet deployed */
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = ZITLAS_CONFIG;
}
