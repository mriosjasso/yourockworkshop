import { Component, Inject, ChangeDetectionStrategy, ViewEncapsulation } from '@angular/core';

@Component({
  changeDetection: ChangeDetectionStrategy.Default,
  encapsulation: ViewEncapsulation.Emulated,
  selector: 'about',
  template: `Hi, we are Mariana and Jisel from IBM Guadalajara! It's been a pleasure to meet you all!`
})
export class AboutComponent {
  constructor(@Inject('req') req: any) {
    // console.log('req',  req)

  }
}
