@Component
export struct SectionTitle {
  @Prop text: string = '';
  build() { Text(this.text).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%').margin({ top: 20, bottom: 10 }); }
}

@Component
export struct InfoCard {
  @Prop title: string = '';
  @Prop body: string = '';
  build() {
    Column({ space: 6 }) {
      Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%');
      Text(this.body).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%');
    }.padding(16).width('100%').alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.surface'))
      .borderRadius(16).border({ width: 1, color: $r('app.color.border') });
  }
}

export function shortError(error: Object): string {
  const raw = String(error); return raw.length > 100 ? raw.slice(0, 100) : raw;
}
