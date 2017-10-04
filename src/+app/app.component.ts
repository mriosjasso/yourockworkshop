import { Component, Directive, ElementRef, Renderer, ChangeDetectionStrategy, ViewEncapsulation } from '@angular/core';

//
/////////////////////////
// ** Example Directive
// Notice we don't touch the Element directly

@Directive({
  selector: '[xLarge]'
})
export class XLargeDirective {
  constructor(element: ElementRef, renderer: Renderer) {
    // ** IMPORTANT **
    // we must interact with the dom through -Renderer-
    // for webworker/server to see the changes
    renderer.setElementStyle(element.nativeElement, 'fontSize', 'x-large');
    // ^^
  }
}

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  encapsulation: ViewEncapsulation.Emulated,
  selector: 'app',
  styles: [`
    * { padding:0; margin:0; font-family: 'Helvetica Neue', sans-serif; }
    #universal { text-align:center; font-weight:bold; padding:15px 0; }
    nav { background: #88d8be; min-height:40px; border-bottom:5px #046923 solid; }
    nav a { font-weight:bold; text-decoration:none; color:#fff; padding:20px; display:inline-block; }
    nav a:hover { background:#316659; }
    .hero-universal { min-height:500px; display:block; padding:20px; background: url('/assets/vancouver.jpg') no-repeat center center; }
    .inner-hero { background: rgba(255, 255, 255, 0.75); border:5px #ccc solid; padding:25px; }
    .router-link-active { background-color: #8ed1c1; }
    main { padding:20px 0; }
    pre { font-size:12px; }
  `],
  template: `
  <h1>You Rock with DevOps!</h1>
  <nav>
    <a routerLinkActive="router-link-active" routerLink="home">Home</a>
    <a routerLinkActive="router-link-active" routerLink="about">About Us</a>
  </nav>
  <div class="hero-universal">
    <div class="inner-hero">
      <div>
        <span xLarge>You Rock With DevOps, {{ title }}!</span>
      </div>

      Type here your name: <input type="text" [value]="title" (input)="title = $event.target.value">

      <br>
      <br>

      <main>
        <router-outlet></router-outlet>
      </main>
    </div>
  </div>
  `
})
export class AppComponent {
  title = '';
}
