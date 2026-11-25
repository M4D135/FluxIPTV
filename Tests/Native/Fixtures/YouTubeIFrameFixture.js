// Local IFrame API boundary used only by FLUX_TRAILER_TESTING. This does not
// contain a video or prove live YouTube playback. The production wrapper,
// WKWebView bridge, SwiftUI hosts, and native session remain unchanged.
window.fixture = {
  constructions: 0,
  commands: [],
  player: null,
  readyTimestamp: null,
  playTimestamp: null,
  ready() {
    this.readyTimestamp = performance.now();
    this.player.options.events.onReady({target: this.player});
    return true;
  },
  state(value) {
    this.player.state = value;
    this.player.options.events.onStateChange({target: this.player, data: value});
    return true;
  },
  metrics(time, duration) {
    this.player.time = time;
    this.player.duration = duration;
    return true;
  },
  error(value) {
    this.player.options.events.onError({target: this.player, data: value});
    return true;
  },
  blocked() {
    this.player.options.events.onAutoplayBlocked({target: this.player});
    return true;
  },
  staleMessage() {
    window.webkit.messageHandlers.fluxTrailer.postMessage({
      type: 'state', value: 0, session: 'not-the-current-session'
    });
    return true;
  },
  childReady() {
    return this.player.frame.contentDocument.readyState === 'complete';
  },
  childMessage() {
    const body = JSON.stringify({type: 'state', value: 0, session: settings.session});
    this.player.frame.contentWindow.eval(
      'window.webkit.messageHandlers.fluxTrailer.postMessage(' + body + ');'
    );
    return true;
  },
  scheduleLateMessage() {
    const handler = window.webkit.messageHandlers.fluxTrailer;
    const body = {type: 'state', value: 1, session: settings.session};
    setTimeout(() => handler.postMessage(body), 250);
    return true;
  }
};

window.YT = {
  Player: class {
    constructor(element, options) {
      this.options = options;
      this.time = 0;
      this.duration = 0;
      this.state = -1;
      this.muted = false;
      this.frame = document.createElement('iframe');
      this.frame.id = element;
      this.frame.srcdoc = '<!doctype html><html><body></body></html>';
      document.getElementById(element).replaceWith(this.frame);
      window.fixture.constructions += 1;
      window.fixture.player = this;
    }
    getIframe() { return this.frame; }
    getCurrentTime() { return this.time; }
    getDuration() { return this.duration; }
    getPlayerState() { return this.state; }
    isMuted() { return this.muted; }
    mute() { this.muted = true; window.fixture.commands.push('mute'); }
    unMute() { this.muted = false; window.fixture.commands.push('unmute'); }
    playVideo() {
      // Deliberately do not emit PLAYING. The native test must distinguish
      // an accepted play command / ready signal from a real state event.
      window.fixture.commands.push('play');
      window.fixture.playTimestamp = performance.now();
    }
    pauseVideo() { window.fixture.commands.push('pause'); }
    seekTo(value) { this.time = value; window.fixture.commands.push('seek'); }
    stopVideo() { window.fixture.commands.push('stop'); }
    destroy() { this.frame.remove(); window.fixture.commands.push('destroy'); }
  }
};
