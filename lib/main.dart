import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const StockApp()); }
class StockApp extends StatelessWidget {
  const StockApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false,title:'SS OIL Stok Kontrol',theme:ThemeData(colorSchemeSeed:const Color(0xFFD51B23),useMaterial3:true,scaffoldBackgroundColor:const Color(0xFFF6F7F9)),home:const Home());
}
void _disposeLater(List<TextEditingController> controllers) {
  Future<void>.delayed(const Duration(milliseconds:500),(){for(final c in controllers){c.dispose();}});
}
class Product {
  final String code,name,barcode,price,stock;
  const Product(this.code,this.name,this.barcode,this.price,this.stock);
  Map<String,dynamic> toJson()=>{'code':code,'name':name,'barcode':barcode,'price':price,'stock':stock};
  factory Product.fromJson(Map<String,dynamic> j)=>Product('${j['code']??''}','${j['name']??''}','${j['barcode']??''}','${j['price']??''}','${j['stock']??''}');
}
class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> {
  // Catalog keys are Artikal IDs, not barcodes. The catalog survives count resets.
  final Map<String,Product> catalog={};
  final Map<String,List<String>> barcodesById={};
  final Map<String,Map<String,String>> barcodeErrors={};
  final Map<String,String> baseStock={};
  String serverUrl='http://192.168.100.13:8766';
  String accessToken='';
  bool sqlBusy=false;
  String cloudUrl='', cloudAnonKey='', cloudSyncPath='/rest/v1/ss_oil_snapshots';
  String cloudRefreshPath='/rest/v1/ss_oil_refresh_requests', cloudMode='Otomatik';
  int syncMinutes=30, requestTimeout=15;
  String salesPath='/fuel-sales', fuelMapping='{}', cloudStationId='ss-oil';
  final Map<String,double> fuelEntries={'Dizel':0,'Dizel+':0,'Benzin':0};
  final Map<String,Map<String,double>> processedFuel={};


  final Map<String,Map<String,dynamic>> issues={};
  final Map<String,Product> orders={};
  final Map<String,OrderLine> orderLines={};
  final Map<String,String> suppliers={};
  final Map<String,String> productSuppliers={};
  final Map<String,String> preferredUnits={};
  Product? current;
  final Map<String,int> labelQueue={};
  final Map<String,Map<String,double>> labelSettings={};
  final Map<String,List<int>> supplierDays={};
  final count=TextEditingController();
  final search=TextEditingController();
  String status='Ürün listesi yükleyin veya barkod okutun';
  @override void initState(){
    super.initState();
    _load();
  }
  @override void dispose(){
    count.dispose();search.dispose();super.dispose();
  }
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    try {
      final c=jsonDecode(p.getString('catalog')??'[]') as List;
      final i=jsonDecode(p.getString('issues')??'[]') as List;
      final o=jsonDecode(p.getString('orders')??'[]') as List;
      serverUrl=p.getString('sql_server_url')??serverUrl;
      accessToken=p.getString('sql_api_token')??'';
      cloudUrl=p.getString('cloud_url')??'';
      cloudAnonKey=p.getString('cloud_anon_key')??'';
      cloudSyncPath=p.getString('cloud_sync_path')??cloudSyncPath;
      cloudRefreshPath=p.getString('cloud_refresh_path')??cloudRefreshPath;
      cloudMode=p.getString('cloud_mode')??cloudMode;
      cloudStationId=p.getString('cloud_station_id')??cloudStationId;
      salesPath=p.getString('fuel_sales_path')??salesPath;
      fuelMapping=p.getString('fuel_mapping')??fuelMapping;
      syncMinutes=p.getInt('sync_minutes')??syncMinutes;
      requestTimeout=p.getInt('request_timeout')??requestTimeout;
      final fe=jsonDecode(p.getString('fuel_entries')??'{}') as Map;
      final pf=jsonDecode(p.getString('fuel_processed')??'{}') as Map;
      for(final e in fe.entries){fuelEntries['${e.key}']=(e.value as num).toDouble();}
      for(final e in pf.entries){processedFuel['${e.key}']=Map<String,double>.from((e.value as Map).map((k,v)=>MapEntry('$k',(v as num).toDouble())));}

      final bs=jsonDecode(p.getString('base_stock')??'{}') as Map;
      final bm=jsonDecode(p.getString('barcode_map')??'{}') as Map;
      final be=jsonDecode(p.getString('barcode_errors')??'{}') as Map;
      final sl=jsonDecode(p.getString('supplier_list')??'{}') as Map;
      final ps=jsonDecode(p.getString('product_suppliers')??'{}') as Map;
      final pu=jsonDecode(p.getString('preferred_units')??'{}') as Map;
      final ol=jsonDecode(p.getString('order_lines')??'[]') as List;
      final lq=jsonDecode(p.getString('label_queue')??'{}') as Map;
      final ls=jsonDecode(p.getString('label_settings')??'{}') as Map;
      final sd=jsonDecode(p.getString('supplier_days')??'{}') as Map;

      setState((){
        for(final x in c){final a=Product.fromJson(Map<String,dynamic>.from(x));if(a.code.isNotEmpty)catalog[a.code]=a;}
        for(final x in i){final m=Map<String,dynamic>.from(x);issues['${m['code']}']=m;}
        for(final x in o){final a=Product.fromJson(Map<String,dynamic>.from(x));orders[a.code]=a;}
        for(final e in bs.entries){baseStock['${e.key}']='${e.value}';}
        for(final e in bm.entries){barcodesById['${e.key}']=List<String>.from(e.value as List);}
        for(final e in be.entries){barcodeErrors['${e.key}']=Map<String,String>.from(e.value as Map);}
        for(final e in sl.entries){suppliers['${e.key}']='${e.value}';}
        for(final e in ps.entries){productSuppliers['${e.key}']='${e.value}';}
        for(final e in pu.entries){preferredUnits['${e.key}']='${e.value}';}
        for(final e in lq.entries){labelQueue['${e.key}']=(e.value as num).toInt();}
        for(final e in ls.entries){labelSettings['${e.key}']=Map<String,double>.from((e.value as Map).map((k,v)=>MapEntry('$k',(v as num).toDouble())));}
        for(final e in sd.entries){supplierDays['${e.key}']=List<int>.from(e.value as List);}
        for(final e in ol){final line=OrderLine.fromJson(Map<String,dynamic>.from(e));orderLines[line.code]=line;}
        // Older versions stored products without quantities. Do not invent an order amount.
        orders.clear();

      });
    } catch(_){setState(()=>status='Kayıt okuma hatası');}
  }
  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('catalog',jsonEncode(catalog.values.map((x)=>x.toJson()).toList()));
    await p.setString('issues',jsonEncode(issues.values.toList()));
    await p.setString('orders',jsonEncode(orders.values.map((x)=>x.toJson()).toList()));
    await p.setString('base_stock',jsonEncode(baseStock));
    await p.setString('barcode_map',jsonEncode(barcodesById));
    await p.setString('barcode_errors',jsonEncode(barcodeErrors));
    await p.setString('supplier_list',jsonEncode(suppliers));
    await p.setString('product_suppliers',jsonEncode(productSuppliers));
    await p.setString('preferred_units',jsonEncode(preferredUnits));
    await p.setString('order_lines',jsonEncode(orderLines.values.map((x)=>x.toJson()).toList()));
    await p.setString('label_queue',jsonEncode(labelQueue));
    await p.setString('label_settings',jsonEncode(labelSettings));
    await p.setString('supplier_days',jsonEncode(supplierDays));
    await p.setString('sql_server_url',serverUrl);
    await p.setString('sql_api_token',accessToken);
    await p.setString('cloud_url',cloudUrl);
    await p.setString('cloud_anon_key',cloudAnonKey);
    await p.setString('cloud_sync_path',cloudSyncPath);
    await p.setString('cloud_refresh_path',cloudRefreshPath);
    await p.setString('cloud_mode',cloudMode);
    await p.setString('cloud_station_id',cloudStationId);
    await p.setString('fuel_sales_path',salesPath);
    await p.setString('fuel_mapping',fuelMapping);
    await p.setInt('sync_minutes',syncMinutes);
    await p.setInt('request_timeout',requestTimeout);
    await p.setString('fuel_entries',jsonEncode(fuelEntries));
    await p.setString('fuel_processed',jsonEncode(processedFuel));


  }
  void _msg(String s){if(mounted){setState(()=>status=s);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),duration:const Duration(seconds:1)));}}
  Future<Map<String,dynamic>> _api(String route) async {
    final url=Uri.parse('${serverUrl.replaceAll(RegExp(r'/+$'), '')}$route');
    final response=await http.get(url,headers:{'X-SSOIL-Token':accessToken})
        .timeout(Duration(seconds:requestTimeout));
    if(response.statusCode!=200)throw Exception('Sunucu HTTP ${response.statusCode}: ${response.body}');
    return Map<String,dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
  }
  String _number(dynamic v)=>v==null?'0':'$v'.replaceAll(',','.');
  Future<void> _sqlSettings() async {
    final host=TextEditingController(text:serverUrl);
    final token=TextEditingController(text:accessToken);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('SQL bağlantı servisi'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:host,decoration:const InputDecoration(labelText:'Bilgisayar servis adresi')),
        TextField(controller:token,obscureText:true,decoration:const InputDecoration(labelText:'API erişim anahtarı')),
        const SizedBox(height:8),const Text('SQL şifresi telefona girilmez. Bilgisayardaki salt-okunur servis kullanılır.'),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Vazgeç')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Kaydet'))]));
    if(ok==true){serverUrl=host.text.trim();accessToken=token.text.trim();await _save();_msg('Bağlantı ayarları kaydedildi');}
    _disposeLater([host,token]);
  }
  Future<void> _sqlRefresh() async {
    if(sqlBusy)return;
    setState(()=>sqlBusy=true);
    try {
      final result=await _api('/snapshot');
      final products=List<Map<String,dynamic>>.from((result['products'] as List).map((e)=>Map<String,dynamic>.from(e as Map)));
      final nextCatalog=<String,Product>{};
      final nextBase=<String,String>{};
      final nextBarcodes=<String,List<String>>{};
      for(final r in products){
        final id='${r['id']}';
        if(id.isEmpty)continue;
        final bars=List<String>.from((r['barcodes'] as List? ?? []).map((e)=>'$e')).where((e)=>e.isNotEmpty).toSet().toList();
        final old=catalog[id];
        final price=_number(r['price']);
        final stock=_number(r['stock']);
        nextBase[id]=stock;
        nextBarcodes[id]=bars;
        nextCatalog[id]=Product(id,'${r['name']??old?.name??''}',bars.isNotEmpty?bars.first:(old?.barcode??''),price,stock);
      }
      // Merge instead of deleting locally added products and count records.
      catalog.addAll(nextCatalog);
      baseStock.addAll(nextBase);
      barcodesById.addAll(nextBarcodes);
      await _save();
      if(mounted)setState(()=>current=current==null?null:catalog[current!.code]);
      _msg('${nextCatalog.length} ürün ve barkodları güncellendi');
    }catch(e){_msg('Stok güncelleme başarısız: $e');}
    finally{if(mounted)setState(()=>sqlBusy=false);}
  }
  Future<void> _barcodeProblem(String barcode,String reason,{String id=''}) async {
    final idCtrl=TextEditingController(text:id);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(reason),content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Barkod: $barcode'),TextField(controller:idCtrl,keyboardType:TextInputType.number,
          decoration:const InputDecoration(labelText:'Doğru Artikal ID (isteğe bağlı)')),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Vazgeç')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Hata listesine kaydet'))]));
    if(ok==true){barcodeErrors[barcode]={'id':idCtrl.text.trim(),'barcode':barcode,'error':reason};await _save();_msg('Barkod hata listesine kaydedildi');}
    _disposeLater([idCtrl]);
  }
  Future<void> _lookupBarcode(String barcode) async {
    final ids=barcodesById.entries.where((e)=>e.value.contains(barcode)).map((e)=>e.key).toList();
    if(ids.isEmpty){await _barcodeProblem(barcode,'Barkod kayıtlı değil');return;}
    String? selected;
    if(ids.length==1){selected=ids.first;}
    else {
      final controller=TextEditingController();
      selected=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Çift ürün – Doğru ID seç'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          for(final id in ids)ListTile(title:Text('ID $id'),subtitle:Text(catalog[id]?.name??''),onTap:()=>Navigator.pop(ctx,id)),
          TextField(controller:controller,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Artikal ID elle gir')),
        ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('İptal')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('ID ile devam'))]));
      _disposeLater([controller]);
      if(selected!=null&&selected.isNotEmpty){barcodeErrors[barcode]={'id':selected,'barcode':barcode,'error':'Çift ürün'};await _save();}
    }
    if(selected==null||selected.isEmpty)return;
    if(!catalog.containsKey(selected)){await _barcodeProblem(barcode,'Yanlış barkod',id:selected);return;}
    await _refreshOne(selected);
  }
  Future<void> _refreshOne(String id) async {
    if(sqlBusy)return;
    setState(()=>sqlBusy=true);
    try {
      final result=await _api('/product/${Uri.encodeComponent(id)}');
      final old=catalog[id];
      if(old==null)throw Exception('Önce Stok Güncelle yapın');
      final stock=_number(result['stock']);
      final price=_number(result['price']);
      final updated=Product(id,old.name,old.barcode,price,stock);
      catalog[id]=updated;
      await _save();
      if(mounted)setState((){current=updated;count.clear();});
      _msg('ID $id: güncel stok $stock');
    }catch(e){_msg('Anlık sorgu hatası: $e');}
    finally{if(mounted)setState(()=>sqlBusy=false);}
  }
  Future<void> _scan() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanPage()));
    if(code==null||!mounted)return;
    await _lookupBarcode(code.trim());
  }
  Future<void> _addManual() async {
    final id=TextEditingController(),name=TextEditingController(),barcode=TextEditingController(),price=TextEditingController(),stock=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Manuel ürün ekle'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final field in <(TextEditingController,String)>[(id,'Artikal ID'),(name,'Ürün adı'),(barcode,'Barkod'),(price,'Fiyat'),(stock,'Stok')])
          Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:field.$1,decoration:InputDecoration(labelText:field.$2,border:const OutlineInputBorder()))),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Kaydet'))]));
    if(ok==true){
      final code=id.text.trim(),ean=barcode.text.trim();
      if(code.isEmpty||name.text.trim().isEmpty||ean.isEmpty){_msg('ID, isim ve barkod gerekli');}
      else if(catalog.containsKey(code)||catalog.values.any((x)=>x.barcode==ean)){_msg('Bu ID veya barkod zaten kayıtlı');}
      else {catalog[code]=Product(code,name.text.trim(),ean,price.text.trim(),stock.text.trim());await _save();setState((){current=catalog[code];});_msg('Ürün kalıcı olarak kaydedildi');}
    }
    _disposeLater([id,name,barcode,price,stock]);
  }
  Future<void> _editCurrent() async {
    final p=current;if(p==null)return;
    final price=TextEditingController(text:p.price),stock=TextEditingController(text:p.stock);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text('Stok ve fiyat – ${p.code}'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:price,decoration:const InputDecoration(labelText:'Satış fiyatı')),
        TextField(controller:stock,decoration:const InputDecoration(labelText:'Stok miktarı'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Kaydet'))]));
    if(ok==true){final updated=Product(p.code,p.name,p.barcode,price.text.trim(),stock.text.trim());catalog[p.code]=updated;await _save();if(mounted)setState(()=>current=updated);_msg('Fiyat ve stok güncellendi');}
    _disposeLater([price,stock]);
  }
  // Excel/CSV import is update-only. Unknown Artikal IDs are skipped.
  Future<void> _import() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['xlsx','csv']);
    if(r==null||r.files.single.path==null)return;
    try {
      final file=File(r.files.single.path!);
      List<List<String>> rows=[];
      if(file.path.toLowerCase().endsWith('.xlsx')){
        final book=xl.Excel.decodeBytes(await file.readAsBytes());
        final sheet=book.tables.values.first;
        if(sheet==null)throw Exception('Excel sayfası boş');
        rows=sheet.rows.map((r)=>r.map((c)=>c?.value?.toString()??'').toList()).toList();
      } else {
        final raw=await file.readAsString();
        final delimiter=raw.split('\n').first.contains(';')?';':',';
        rows=CsvToListConverter(fieldDelimiter:delimiter,shouldParseNumbers:false).convert(raw)
          .map((r)=>r.map((x)=>x.toString()).toList()).toList();
      }
      if(rows.length<2)throw Exception('Ürün satırı bulunamadı');
      String norm(String s)=>s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9ğüşöçıа-я]'), '');
      final h=rows.first.map(norm).toList();
      int idx(List<String> opts){for(final x in opts){final i=h.indexOf(norm(x));if(i>=0)return i;}return -1;}
      final ci=idx(['artikal id','artikalid','code','ürün kodu','urun kodu','šifra']);
      final pi=idx(['price','fiyat','cijena','prodajna cijena','satış fiyatı']);
      final si=idx(['stock','stok','stanje','količina','kolicina']);
      if(ci<0 || (pi<0&&si<0))throw Exception('Başlıklar: Artikal ID, Fiyat, Stok');
      String cell(List<String> row,int i)=>i<0||i>=row.length?'':row[i].trim();
      int changed=0,skipped=0;
      for(final row in rows.skip(1)){
        final id=cell(row,ci);final old=catalog[id];
        if(old==null){skipped++;continue;}
        final price=cell(row,pi),stock=cell(row,si);
        if(price.isEmpty&&stock.isEmpty)continue;
        catalog[id]=Product(old.code,old.name,old.barcode,price.isEmpty?old.price:price,stock.isEmpty?old.stock:stock);
        changed++;
      }
      await _save();if(current!=null && mounted){setState(()=>current=catalog[current!.code]);}
      _msg('$changed kayıt güncellendi; $skipped kayıtlı olmayan ID atlandı');
    }catch(e){_msg('Excel aktarım hatası: $e');}
  }
  void _issue(String type) {
    final p=current;if(p==null)return;
    final existing=issues[p.code]??{'code':p.code,'name':p.name,'barcode':p.barcode,'price':p.price,'stock':p.stock,'count':'','types':<String>[]};
    // Always compare against the current single stock value.
    existing['price']=p.price;
    existing['stock']=p.stock;
    final types=List<String>.from(existing['types'] as List);
    if(type=='Eksik'||type=='Fazla'){
      final q=double.tryParse(count.text.replaceAll(',','.'));
      final s=double.tryParse(p.stock.replaceAll(',','.'));
      if(q==null||q<0||s==null){_msg('Geçerli sayılan miktar ve sistem stoku gerekli');return;}
      if(type=='Eksik'&&q>=s || type=='Fazla'&&q<=s){_msg('Sayılan stok ile seçilen durum uyuşmuyor');return;}
      types.remove('Eksik');types.remove('Fazla');existing['count']=count.text;
    }
    if(type=='Sorun Yok'){types.clear();existing['count']='';}else{types.remove('Sorun Yok');}
    if(!types.contains(type))types.add(type);
    existing['types']=types;
    issues[p.code]=existing;
    unawaited(_save());_msg('$type kaydedildi / mevcut kayıt güncellendi');setState((){});
  }
  void _ok(){_issue('Sorun Yok');}
  Future<void> _order() async {final p=current;if(p!=null)await _addOrder(p);}
  Future<void> _addOrder(Product product) async {
    if(suppliers.isEmpty){_msg('Önce Ayarlar bölümünden tedarikçi ekleyin');return;}
    final old=orderLines[product.code];
    String? supplier=productSuppliers[product.code];
    if(!suppliers.containsKey(supplier))supplier=null;
    String unit=old?.unit??preferredUnits[product.code]??'kom';
    final qty=TextEditingController(text:old?.quantity.toString()??'1');
    final chosen=await showDialog<OrderLine>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
      title:const Text('Siparişe Ekle'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(product.name,style:const TextStyle(fontWeight:FontWeight.bold)),
        Text('Barkod: ${product.barcode}'),const SizedBox(height:12),
        DropdownButtonFormField<String>(value:supplier,decoration:const InputDecoration(labelText:'Tedarikçi',border:OutlineInputBorder()),
          items:suppliers.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
          onChanged:(v)=>update(()=>supplier=v)),
        const SizedBox(height:12),
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Količina',border:OutlineInputBorder())),
        const SizedBox(height:10),
        SegmentedButton<String>(segments:const [ButtonSegment(value:'kom',label:Text('kom')),ButtonSegment(value:'pak',label:Text('pak'))],selected:{unit},onSelectionChanged:(v)=>update(()=>unit=v.first)),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('İptal')),
        FilledButton(onPressed:(){final n=int.tryParse(qty.text.trim());if(supplier==null||n==null||n<=0){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('Tedarikçi ve pozitif tam sayı girin')));return;}
          Navigator.pop(ctx,OrderLine(product.code,product.name,product.barcode,supplier!,n,unit));},child:const Text('Siparişe Ekle'))],
    )));
    _disposeLater([qty]);if(chosen==null)return;
    // If the same product, supplier and unit are chosen again, add the quantities.
    final previous=orderLines[product.code];
    final total=chosen.quantity;
    orderLines[product.code]=chosen.withQuantity(total);
    productSuppliers[product.code]=chosen.supplierId;
    preferredUnits[product.code]=chosen.unit;
    await _save();if(mounted)setState((){});_msg('Siparişe eklendi: $total ${chosen.unit}');
  }
  Future<void> _manageSuppliers() async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>SupplierPage(suppliers:suppliers,usedIds:{...productSuppliers.values,...orderLines.values.map((e)=>e.supplierId)},onChanged:()async{await _save();if(mounted)setState((){});}))); 
  }
  Future<void> _settings() async {
    await Navigator.push(context,MaterialPageRoute(builder:(ctx)=>Scaffold(appBar:AppBar(title:const Text('Ayarlar')),body:ListView(children:[
      ListTile(leading:const Icon(Icons.local_shipping_outlined),title:const Text('Tedarikçiler'),onTap:()async{await _manageSuppliers();}),
      ListTile(leading:const Icon(Icons.sync),title:const Text('Stok Güncelle'),subtitle:const Text('Yalnızca elle güncelle'),onTap:()async{Navigator.pop(ctx);await _sqlRefresh();}),
      ListTile(leading:const Icon(Icons.print_outlined),title:const Text('Etiket Baskı Ayarları'),onTap:()=>_labelSettingsPage()),
      ListTile(leading:const Icon(Icons.calendar_month),title:const Text('Tedarikçi Sipariş Günleri'),onTap:()=>_supplierDaysPage()),
      ListTile(leading:const Icon(Icons.settings_ethernet),title:const Text('Yerel Ağ / API Ayarları'),onTap:()async{Navigator.pop(ctx);await _sqlSettings();}),
      ListTile(leading:const Icon(Icons.cloud_outlined),title:const Text('Bulut / Supabase Ayarları'),subtitle:const Text('Sunucu, anahtar, yollar, senkronizasyon'),onTap:()=>_cloudSettings()),
      ListTile(leading:const Icon(Icons.local_gas_station),title:const Text('Yakıt Stok Girişi'),subtitle:const Text('Girişler mevcut stoğa eklenir'),onTap:()=>_fuelEntryPage()),
      ListTile(leading:const Icon(Icons.tune),title:const Text('Yakıt Satış Eşleştirmesi'),subtitle:const Text('SMPS alanları ve satış API yolu'),onTap:()=>_fuelMappingPage()),
      const Divider(),
      ListTile(leading:const Icon(Icons.delete_forever_outlined,color:Colors.red),title:const Text('Stok Kontrol Kayıtlarını Temizle'),subtitle:const Text('Sipariş listesi ve tedarikçiler korunur'),onTap:()async{Navigator.pop(ctx);await _clear();}),
    ]))));
  }

  Map<String,double> _labelCfg(String type) => labelSettings[type] ?? {
    'w':type=='a4'?44:38,'h':type=='a4'?36:25,
    'cols':type=='a4'?4:3,'rows':type=='a4'?8:3,
    'left':type=='a4'?10:2,'top':type=='a4'?4.5:2,
    'gapX':0,'gapY':0,'font':type=='a4'?9:7,'barcodeH':type=='a4'?9:5,
    'pageW':type=='a4'?210:120,'pageH':type=='a4'?297:83,
  };
  Future<void> _labelSettingsPage() async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>LabelSettingsPage(
      current:_labelCfg,save:(type,settings)async{labelSettings[type]=settings;await _save();}))); 
  }
  Future<void> _supplierDaysPage() async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>SupplierDaysPage(
      suppliers:suppliers,days:supplierDays,onSave:()async{await _save();}))); 
  }
  Future<void> _labelPage() async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>LabelQueuePage(
      catalog:catalog,queue:labelQueue,refreshProduct:(id)async{
        final data=await _api('/product/${Uri.encodeComponent(id)}');
        final old=catalog[id]!;
        if(data['price']==null)throw Exception('Sunucu güncel fiyat göndermedi');
        final updated=Product(id,old.name,old.barcode,'${data['price']}','${data['stock']??old.stock}');
        catalog[id]=updated;await _save();return updated;
      },settings:_labelCfg,onSave:()async{await _save();}))); 
    if(mounted)setState((){});
  }
  Future<void> _riskPage() async {
    // Top-200 determination requires a valid dated sales feed. Never invent ranking.
    Map<String,double> sold={};bool verified=false;
    try{
      final data=await _api('/sales?days=7');
      if(data['period_days']==7 && data['sales'] is Map){
        sold=(data['sales'] as Map).map((k,v)=>MapEntry('$k',double.tryParse('$v')??0));verified=true;
      }
    }catch(_){/* Stock risk still works without sales data. */}
    if(!mounted)return;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>RiskPage(
      catalog:catalog,sold:sold,verified:verified,onOrder:_addOrder)));
  }
  Future<void> _topSellersPage() async {
    try{
      final data=await _api('/sales?days=7');
      if(data['period_days']!=7 || data['sales'] is! Map)throw Exception('7 günlük doğrulanmış satış verisi yok');
      final sales=(data['sales'] as Map).map((k,v)=>MapEntry('$k',double.tryParse('$v')??0.0));
      final ranked=sales.entries.where((e)=>catalog.containsKey(e.key)).toList()..sort((a,b)=>b.value.compareTo(a.value));
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('Son 7 Gün • İlk 200')),
        body:ListView(children:ranked.take(200).map((e)=>ListTile(title:Text(catalog[e.key]!.name),subtitle:Text('Kod: ${e.key}'),trailing:Text('${e.value} adet'))).toList()))));
    }catch(e){_msg('Çok Satanlar için sunucuda 7 günlük satış API desteği gerekli: $e');}
  }
  double _remainingFuel(String name) => (fuelEntries[name]??0)-processedFuel.values.fold<double>(0,(sum,entry)=>sum+(entry[name]??0));
  Future<void> _fuelEntryPage() async {
    await Navigator.push(context,MaterialPageRoute(builder:(ctx)=>Scaffold(appBar:AppBar(title:const Text('Yakıt Stok Girişi')),body:ListView(children:[
      const Padding(padding:EdgeInsets.all(16),child:Text('Girilen litre mevcut stoğa EKLENİR. SMPS satışları Broj bazında yalnızca bir kez düşülür.')),
      for(final name in ['Dizel','Dizel+','Benzin']) ListTile(title:Text(name),subtitle:Text('Toplam giriş: ${(fuelEntries[name]??0).toStringAsFixed(2)} L'),trailing:Text('${_remainingFuel(name).toStringAsFixed(2)} L'),onTap:()async{
        final c=TextEditingController();
        final value=await showDialog<double>(context:ctx,builder:(d)=>AlertDialog(title:Text('$name • Litre Ekle'),content:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Gelen yakıt (litre)')),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('İptal')),FilledButton(onPressed:()=>Navigator.pop(d,double.tryParse(c.text.replaceAll(',','.'))),child:const Text('Ekle'))]));
        _disposeLater([c]);
        if(value!=null && value>0){fuelEntries[name]=(fuelEntries[name]??0)+value;await _save();if(mounted)setState((){});}
      }),
      const Padding(padding:EdgeInsets.all(16),child:Text('Not: Bu sürümde satış kaynağı henüz doğrulanmadığı için SMPS satışları otomatik içeri alınmaz.')),
    ]))));
  }
  Future<void> _cloudSettings() async {
    final fields=<String,TextEditingController>{
      'Supabase Proje URL':TextEditingController(text:cloudUrl),
      'Supabase Publishable / Anon Key':TextEditingController(text:cloudAnonKey),
      'İstasyon Kimliği':TextEditingController(text:cloudStationId),
      'Veri Yolu':TextEditingController(text:cloudSyncPath),
      'Güncelleme İstek Yolu':TextEditingController(text:cloudRefreshPath),
      'Senkronizasyon Aralığı (dakika)':TextEditingController(text:'$syncMinutes'),
      'Bağlantı Zaman Aşımı (saniye)':TextEditingController(text:'$requestTimeout'),
    };
    var selected=cloudMode;
    await Navigator.push(context,MaterialPageRoute(builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>Scaffold(appBar:AppBar(title:const Text('Bulut / Supabase Ayarları')),body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Bu alanlar APK değiştirmeden düzenlenebilir. Supabase service_role / secret anahtarını telefona GİRMEYİN. Gerçek senkronizasyon PC servisinde ayrıca kurulacaktır.'),
      const SizedBox(height:12),
      for(final e in fields.entries) Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:e.value,decoration:InputDecoration(labelText:e.key,border:const OutlineInputBorder()),obscureText:e.key.contains('Key'))),
      DropdownButtonFormField<String>(value:selected,decoration:const InputDecoration(labelText:'Bağlantı modu'),items:['Otomatik','Yerel Ağ','Bulut'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>refresh(()=>selected=v??selected)),
      const SizedBox(height:12),FilledButton(onPressed:()async{
        final url=fields['Supabase Proje URL']!.text.trim();
        if(url.isNotEmpty && (Uri.tryParse(url)?.scheme!='https')){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('Bulut adresi https:// ile başlamalı')));return;}
        cloudUrl=url;cloudAnonKey=fields['Supabase Publishable / Anon Key']!.text.trim();cloudStationId=fields['İstasyon Kimliği']!.text.trim();cloudSyncPath=fields['Veri Yolu']!.text.trim();cloudRefreshPath=fields['Güncelleme İstek Yolu']!.text.trim();
        syncMinutes=int.tryParse(fields['Senkronizasyon Aralığı (dakika)']!.text)??30;requestTimeout=int.tryParse(fields['Bağlantı Zaman Aşımı (saniye)']!.text)??15;
        if(syncMinutes<1)syncMinutes=30;if(requestTimeout<1)requestTimeout=15;cloudMode=selected;await _save();if(ctx.mounted)Navigator.pop(ctx);
      },child:const Text('Ayarları Kaydet')),
    ])))));
    _disposeLater(fields.values.toList());
  }
  Future<void> _fuelMappingPage() async {
    final route=TextEditingController(text:salesPath),mapping=TextEditingController(text:fuelMapping);
    await Navigator.push(context,MaterialPageRoute(builder:(ctx)=>Scaffold(appBar:AppBar(title:const Text('Yakıt Satış Eşleştirmesi')),body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('SMPS kaynak alanlarını PC tarafındaki API ile eşleştirmek için hazırlık. Broj tamamlanmış fiştir; aynı Broj altındaki bütün satırlar birlikte hesaplanmalıdır.'),
      const SizedBox(height:16),TextField(controller:route,decoration:const InputDecoration(labelText:'Yerel yakıt satış API yolu',border:OutlineInputBorder())),
      const SizedBox(height:16),TextField(controller:mapping,maxLines:8,decoration:const InputDecoration(labelText:'Yakıt Art_ID eşleştirmesi (JSON)',hintText:'{"123":"Dizel","124":"Dizel+"}',border:OutlineInputBorder())),
      const SizedBox(height:16),FilledButton(onPressed:()async{try{final parsed=jsonDecode(mapping.text);if(parsed is! Map)throw const FormatException('JSON nesnesi gerekli');salesPath=route.text.trim();fuelMapping=mapping.text.trim();await _save();if(ctx.mounted)Navigator.pop(ctx);}catch(_){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('Geçerli JSON girin')));}},child:const Text('Kaydet')),
    ]))));_disposeLater([route,mapping]);
  }
  Future<void> _cashPage() async {
    DateTime selected=DateTime.now();
    String day(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    Future<Map<String,dynamic>> fetch(DateTime d)=>_api('/kasa?date=${day(d)}');
    Future<Map<String,dynamic>> pending=fetch(selected);
    String amount(dynamic v)=>v==null?'Veri doğrulanamadı':'${_number(v)} KM';
    Widget amountRow(String title,dynamic value,{IconData icon=Icons.receipt_long})=>
      ListTile(leading:Icon(icon),title:Text(title),trailing:Text(amount(value),style:const TextStyle(fontWeight:FontWeight.w600)));
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>StatefulBuilder(builder:(ctx,refresh)=>Scaffold(
      appBar:AppBar(title:const Text('SS OIL • Kasa'),actions:[IconButton(icon:const Icon(Icons.refresh),tooltip:'Yenile',onPressed:()=>refresh(()=>pending=fetch(selected)))]),
      body:ListView(children:[
        ListTile(leading:const Icon(Icons.calendar_month),title:Text('Tarih: ${day(selected)}'),trailing:const Icon(Icons.edit_calendar),onTap:()async{
          final picked=await showDatePicker(context:ctx,initialDate:selected,firstDate:DateTime(2020),lastDate:DateTime(2100));
          if(picked!=null)refresh((){selected=picked;pending=fetch(selected);});
        }),
        FutureBuilder<Map<String,dynamic>>(future:pending,builder:(context,snap){
          if(snap.connectionState!=ConnectionState.done)return const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator()));
          if(snap.hasError)return Padding(padding:const EdgeInsets.all(20),child:Text('Kasa bağlantısı başarısız: ${snap.error}\n\nSunucu adresi, 8766 portu ve erişim anahtarını kontrol edin.'));
          final data=snap.data??{};
          final dop= data['dopuna'] is Map ? Map<String,dynamic>.from(data['dopuna'] as Map):<String,dynamic>{};
          final mtel=dop['mtel'] is Map ? Map<String,dynamic>.from(dop['mtel'] as Map):<String,dynamic>{};
          final aero=dop['aero'] is Map ? Map<String,dynamic>.from(dop['aero'] as Map):<String,dynamic>{};
          return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Padding(padding:EdgeInsets.fromLTRB(16,18,16,6),child:Text('Kasa / SmP_Z',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
            amountRow('Nakit',data['cash'],icon:Icons.payments_outlined),
            amountRow('Kart',data['card'],icon:Icons.credit_card),
            amountRow('Toplam',data['total']),
            amountRow('İade',data['refund'],icon:Icons.keyboard_return),
            ListTile(title:const Text('Fiş sayısı'),trailing:Text('${data['receipt_count']??'—'}')),
            const Divider(),
            const Padding(padding:EdgeInsets.fromLTRB(16,12,16,6),child:Text('Dopuna / başarılı işlemler',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
            amountRow('MTEL',mtel['total'],icon:Icons.phone_android),
            if(mtel['total']==null)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text('MTEL: ${mtel['status']??'veri okunamadı'}',style:const TextStyle(fontSize:12))),
            amountRow('AERO',aero['total'],icon:Icons.phone_android),
            if(aero['total']==null)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text('AERO: ${aero['status']??'veri okunamadı'}',style:const TextStyle(fontSize:12))),
            amountRow('Dopuna toplamı',dop['total']),
          ]);
        }),
        const Divider(),
        const Padding(padding:EdgeInsets.fromLTRB(16,12,16,6),child:Text('Yakıt / yerel girişler',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
        for(final name in ['Dizel','Dizel+','Benzin']) ListTile(leading:const Icon(Icons.local_gas_station),title:Text(name),subtitle:const Text('Satışlar doğrulanmadı; yalnızca kayıtlı giriş bakiyesi'),trailing:Text('${_remainingFuel(name).toStringAsFixed(2)} L')),
        const Padding(padding:EdgeInsets.all(16),child:Text('Yakıt satışları henüz fiş bazında doğrulanmadığı için bu miktarlar gerçek kalan stok olarak değerlendirilmemelidir.')),
      ]),
    ))));
  }

  Future<void> _clearOrders() async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Önceki Siparişi Temizle'),content:const Text('Sipariş ürünleri ve miktarları silinecek. Tedarikçi eşleştirmeleri korunacak.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('İptal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Temizle'))]));
    if(ok!=true)return;orderLines.clear();await _save();if(mounted)setState((){});_msg('Sipariş listesi temizlendi');
  }
  Future<void> _exportOrders() async {
    if(orderLines.isEmpty){_msg('Sipariş listesi boş');return;}
    try{
      final book=xl.Excel.createExcel();
      final used=<String>{};
      for(final entry in suppliers.entries){
        final lines=orderLines.values.where((x)=>x.supplierId==entry.key).toList();if(lines.isEmpty)continue;
        var name=entry.value.replaceAll(RegExp(r'[\\/*?:\[\]]'),'_').trim();
        if(name.isEmpty)name='Tedarikci';if(name.length>31)name=name.substring(0,31);
        final base=name;var i=2;while(used.contains(name.toLowerCase())){final suffix='_$i';name='${base.substring(0,base.length>31-suffix.length?31-suffix.length:base.length)}$suffix';i++;}
        used.add(name.toLowerCase());
        final sheet=book[name];sheet.appendRow([xl.TextCellValue('Naziv'),xl.TextCellValue('Barkod'),xl.TextCellValue('Količina')]);
        for(final l in lines){sheet.appendRow([xl.TextCellValue(l.name),xl.TextCellValue(l.barcode),xl.TextCellValue('${l.quantity} ${l.unit}')]);}
      }
      book.delete('Sheet1');final bytes=book.encode();if(bytes==null)throw Exception('Excel oluşturulamadı');
      final now=DateTime.now();final stamp='${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}';
      final path=await FilePicker.platform.saveFile(dialogTitle:'Sipariş Excel dosyasını kaydet',fileName:'SS_OIL_Siparis_$stamp.xlsx',type:FileType.custom,allowedExtensions:['xlsx'],bytes:Uint8List.fromList(bytes));
      if(path!=null)_msg('Sipariş Excel kaydedildi');
    }catch(e){_msg('Sipariş Excel hatası: $e');}
  }
  Future<void> _openOrders() async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>OrdersPage(onSupplierProducts:_openSupplierProducts,lines:orderLines,suppliers:suppliers,onEdit:(id)async{final p=catalog[id];if(p!=null)await _addOrder(p);},onDelete:(id)async{orderLines.remove(id);await _save();},onClear:_clearOrders,onExport:_exportOrders)));if(mounted)setState((){});}
  Future<void> _openProducts() async => _showProducts();
  Future<void> _openSupplierProducts(String supplierId) async => _showProducts(supplierId:supplierId);
  Future<void> _showProducts({String? supplierId}) async {
    if(catalog.isEmpty){_msg('Önce Ayarlar > Stok Güncelle yapın');return;}
    try{
      setState(()=>sqlBusy=true);
      final data=await _api('/sales');
      final sales=Map<String,dynamic>.from(data['sales'] as Map);
      for(final id in catalog.keys.toList()){
        final old=catalog[id]!;
        final base=double.tryParse((baseStock[id]??old.stock).replaceAll(',','.'));
        final sold=double.tryParse('${sales[id]??0}'.replaceAll(',','.'));
        if(base!=null&&sold!=null){catalog[id]=Product(id,old.name,old.barcode,old.price,(base-sold).toStringAsFixed((base-sold)%1==0?0:2));}
      }
      await _save();
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>ProductsPage(catalog:catalog,barcodes:barcodesById,onOrder:_addOrder,supplierId:supplierId,productSuppliers:productSuppliers,supplierName:supplierId==null?null:suppliers[supplierId])));
    }catch(e){_msg('Güncel satışlar alınamadı; eski stok listesi açılmadı: $e');}
    finally{if(mounted)setState(()=>sqlBusy=false);}
  }
  Future<void> _export() async {
    try {
      final book=xl.Excel.createExcel();
      final a=book['Stok Kontrol'],b=book['Siparis Listesi'],c=book['Urun Veritabani'],d=book['Manuel Stok'];
      void row(xl.Sheet s,List<String> vals)=>s.appendRow(vals.map((v)=>xl.TextCellValue(v)).toList());
      row(a,['Artikal ID','Ürün Adı','Barkod','Satış Fiyatı','Sistem Stoku','Sayılan Stok','Fark','Sorunlar']);
      for(final m in issues.values){
        final st=double.tryParse('${m['stock']}'.replaceAll(',','.'));
        final co=double.tryParse('${m['count']}'.replaceAll(',','.'));
        final types=List<String>.from(m['types'] as List);
        row(a,['${m['code']}','${m['name']}','${m['barcode']}','${m['price']}','${m['stock']}','${m['count']}',st!=null&&co!=null?'${co-st}':'',types.join(', ')]);
      }
      row(b,['Naziv','Barkod','Količina']);
      for(final l in orderLines.values){row(b,[l.name,l.barcode,'${l.quantity} ${l.unit}']);}
      row(c,['Artikal ID','Ürün Adı','Barkod','Fiyat','Stok']);
      row(d,['Artikal ID','Fiyat','Stok']);
      for(final p in catalog.values){row(c,[p.code,p.name,p.barcode,p.price,p.stock]);row(d,[p.code,p.price,p.stock]);}
      final e=book['Hatali Barkodlar'];
      row(e,['Artikal ID','Barkod','Hata']);
      for(final r in barcodeErrors.values){row(e,[r['id']??'',r['barcode']??'',r['error']??'']);}
      book.delete('Sheet1');
      final bytes=book.encode();if(bytes==null)throw Exception('Excel oluşturulamadı');
      final now=DateTime.now();
      final stamp='${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour}${now.minute.toString().padLeft(2,'0')}';
      final filename='SS_OIL_Stok_$stamp.xlsx';
      // Android system save dialog, not share-only. User selects destination.
      final path=await FilePicker.platform.saveFile(dialogTitle:'Excel dosyasını kaydet',fileName:filename,
        type:FileType.custom,allowedExtensions:['xlsx'],bytes:Uint8List.fromList(bytes));
      if(path==null){_msg('Kaydetme iptal edildi');return;}
      _msg('Excel kaydedildi: $path');
    }catch(e){_msg('Excel kaydetme hatası: $e');}
  }
  Future<void> _clear() async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Kayıtları temizle?'),content:const Text('Stok kontrol kayıtları silinir. Sipariş listesi, tedarikçiler ve ürün kataloğu korunur.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Temizle'))]));
    if(ok!=true)return;setState((){issues.clear();current=null;count.clear();});await _save();_msg('Yeni kontrol dönemi başladı');
  }
  Future<void> _showIssues(String type) async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>IssuesPage(type:type,issues:issues,onChanged:()async{await _save();if(mounted)setState((){});})));}
  Future<void> _lists() async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>ListPage(issues:issues,orders:orders,onChanged:() async {await _save();setState((){});})));setState((){});}
  @override
  Widget build(BuildContext context) {
    final p=current;
    return Scaffold(
      appBar:AppBar(
        backgroundColor:Colors.black,
        foregroundColor:Colors.white,
        title:const Text('Stok Kontrol',style:TextStyle(fontWeight:FontWeight.w700)),
        actions:[IconButton(tooltip:'Ayarlar',onPressed:_settings,icon:const Icon(Icons.settings_outlined))],
      ),
      bottomNavigationBar:SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,12),child:FilledButton.icon(
        onPressed:_export,icon:const Icon(Icons.file_download_outlined),label:const Text('Stok Excel’e Aktar'),
        style:FilledButton.styleFrom(minimumSize:const Size(0,52),backgroundColor:const Color(0xFF1E754D)),
      ))),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Row(children:[
          ClipRRect(borderRadius:BorderRadius.circular(9),child:Image.asset('assets/ss_oil_logo.jpg',width:56,height:56,fit:BoxFit.contain)),
          const SizedBox(width:12),const Expanded(child:Text('SS OIL • Stok Kontrol',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold))),
        ]),
        const SizedBox(height:16),
        SizedBox(height:54,child:FilledButton.icon(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:const Text('Barkod Oku'))),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:FilledButton.tonalIcon(onPressed:()=>_showIssues('Eksik'),icon:const Icon(Icons.trending_down),label:const Text('Eksik'))),
          const SizedBox(width:10),
          Expanded(child:FilledButton.tonalIcon(onPressed:()=>_showIssues('Fazla'),icon:const Icon(Icons.trending_up),label:const Text('Fazla'))),
        ]),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:_openOrders,icon:const Icon(Icons.shopping_cart_outlined),label:Text('Sipariş (${orderLines.length})'))),
          const SizedBox(width:10),
          Expanded(child:OutlinedButton.icon(onPressed:sqlBusy?null:_openProducts,icon:const Icon(Icons.inventory_2_outlined),label:const Text('Tüm Ürünler'))),
        ]),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:_labelPage,icon:const Icon(Icons.local_offer_outlined),label:const Text('Etiketler'))),
          const SizedBox(width:8),
          Expanded(child:OutlinedButton.icon(onPressed:_riskPage,icon:const Icon(Icons.warning_amber),label:const Text('Stok Riski'))),
        ]),
        Row(children:[
          Expanded(child:TextButton.icon(onPressed:_topSellersPage,icon:const Icon(Icons.bar_chart),label:const Text('Çok Satanlar'))),
          Expanded(child:TextButton.icon(onPressed:_cashPage,icon:const Icon(Icons.point_of_sale),label:const Text('Kasa'))),
        ]),
        Text(status,style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:10),
        TextField(
          controller:search,
          decoration:InputDecoration(
            filled:true,fillColor:Colors.white,border:const OutlineInputBorder(),
            labelText:'Barkod veya ürün kodu',
            suffixIcon:IconButton(icon:const Icon(Icons.search),onPressed:(){
              final v=search.text.trim();
              if(catalog.containsKey(v)){unawaited(_refreshOne(v));}
              else{unawaited(_lookupBarcode(v));}
            }),
          ),
          onSubmitted:(v){
            if(catalog.containsKey(v.trim())){unawaited(_refreshOne(v.trim()));}
            else{unawaited(_lookupBarcode(v.trim()));}
          },
        ),
        const SizedBox(height:12),
        if(p!=null)...[
          Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Kod: ${p.code}'),
              Text(p.name,style:Theme.of(context).textTheme.titleMedium),
              Text('Barkod: ${p.barcode}'),
              Text('Satış: ${p.price} KM     Stok: ${p.stock}',style:Theme.of(context).textTheme.titleSmall),
            ],
          ))),
          const SizedBox(height:12),
          TextField(controller:count,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Gerçek sayılan stok')),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:FilledButton.tonal(onPressed:()=>_issue('Eksik'),child:const Text('Eksik'))),
            const SizedBox(width:8),
            Expanded(child:FilledButton.tonal(onPressed:()=>_issue('Fazla'),child:const Text('Fazla'))),
          ]),
          for(final label in ['Yanlış Barkod','Yanlış Fiyat','Etiket Yok'])
            Padding(padding:const EdgeInsets.only(top:8),child:OutlinedButton(onPressed:()=>_issue(label),child:Text(label))),
          const SizedBox(height:10),
          OutlinedButton(onPressed:_ok,child:const Text('Sorun Yok – Kaydet')),
          FilledButton.icon(onPressed:_order,icon:const Icon(Icons.shopping_cart_outlined),label:const Text('Sipariş Listesine Ekle')),
        ]else const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('Ürün seçmek için barkod okutun veya ürün kodunu girin.'))),
        const SizedBox(height:24),
      ]),
    );
  }
}
class ScanPage extends StatefulWidget {const ScanPage({super.key});@override State<ScanPage> createState()=>_ScanPageState();}
class _ScanPageState extends State<ScanPage>{bool done=false;@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Barkod Tara')),body:MobileScanner(onDetect:(capture){if(done)return;final code=capture.barcodes.firstOrNull?.rawValue;if(code==null||code.isEmpty)return;done=true;Navigator.pop(context,code);}));}
class ListPage extends StatefulWidget {final Map<String,Map<String,dynamic>> issues;final Map<String,Product> orders;final Future<void> Function() onChanged;const ListPage({super.key,required this.issues,required this.orders,required this.onChanged});@override State<ListPage> createState()=>_ListPageState();}
class _ListPageState extends State<ListPage>{@override Widget build(BuildContext context)=>DefaultTabController(length:2,child:Scaffold(appBar:AppBar(title:const Text('Kayıt Listeleri'),bottom:const TabBar(tabs:[Tab(text:'Stok / Hatalar'),Tab(text:'Sipariş')])),body:TabBarView(children:[ListView(children:widget.issues.entries.map((e)=>ListTile(title:Text('${e.value['name']}'),subtitle:Text('Kod: ${e.key} • ${e.value['types'].join(', ')} • Sayılan: ${e.value['count']}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.issues.remove(e.key));await widget.onChanged();}))).toList()),ListView(children:widget.orders.entries.map((e)=>ListTile(title:Text(e.value.name),subtitle:Text('Kod: ${e.value.code} • Barkod: ${e.value.barcode}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.orders.remove(e.key));await widget.onChanged();}))).toList())])));}

class OrderLine {
  final String code,name,barcode,supplierId,unit;
  final int quantity;
  const OrderLine(this.code,this.name,this.barcode,this.supplierId,this.quantity,this.unit);
  OrderLine withQuantity(int q)=>OrderLine(code,name,barcode,supplierId,q,unit);
  Map<String,dynamic> toJson()=>{'code':code,'name':name,'barcode':barcode,'supplierId':supplierId,'quantity':quantity,'unit':unit};
  factory OrderLine.fromJson(Map<String,dynamic> j)=>OrderLine('${j['code']??''}','${j['name']??''}','${j['barcode']??''}','${j['supplierId']??''}',int.tryParse('${j['quantity']}')??1,j['unit']=='pak'?'pak':'kom');
}
class SupplierPage extends StatefulWidget {
  final Map<String,String> suppliers;
  final Set<String> usedIds;
  final Future<void> Function() onChanged;
  const SupplierPage({super.key,required this.suppliers,required this.usedIds,required this.onChanged});
  @override State<SupplierPage> createState()=>_SupplierPageState();
}
class _SupplierPageState extends State<SupplierPage> {
  Future<void> edit([String? id]) async {
    final c=TextEditingController(text:id==null?'':widget.suppliers[id]);
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(id==null?'Tedarikçi Ekle':'Tedarikçi Düzenle'),content:TextField(controller:c,autofocus:true,decoration:const InputDecoration(labelText:'Tedarikçi adı')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('İptal')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Kaydet'))]));
    Future<void>.delayed(const Duration(milliseconds:500),c.dispose);if(result==null||result.isEmpty)return;
    if(widget.suppliers.entries.any((e)=>e.key!=id&&e.value.toLowerCase()==result.toLowerCase())){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Bu tedarikçi zaten kayıtlı')));return;}
    setState(()=>widget.suppliers[id??DateTime.now().microsecondsSinceEpoch.toString()]=result);
    await widget.onChanged();
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Tedarikçiler')),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Ekle')),body:ListView(children:widget.suppliers.entries.map((e)=>ListTile(title:Text(e.value),trailing:Wrap(children:[IconButton(onPressed:()=>edit(e.key),icon:const Icon(Icons.edit_outlined)),IconButton(onPressed:widget.usedIds.contains(e.key)?null:()async{setState(()=>widget.suppliers.remove(e.key));await widget.onChanged();},icon:const Icon(Icons.delete_outline))]))).toList()));
}
class OrdersPage extends StatefulWidget {
  final Map<String,OrderLine> lines;
  final Map<String,String> suppliers;
  final Future<void> Function(String) onEdit,onDelete;
  final Future<void> Function() onClear,onExport;
  final Future<void> Function(String) onSupplierProducts;
  const OrdersPage({super.key,required this.lines,required this.suppliers,required this.onEdit,required this.onDelete,required this.onClear,required this.onExport,required this.onSupplierProducts});
  @override State<OrdersPage> createState()=>_OrdersPageState();
}
class _OrdersPageState extends State<OrdersPage> {
  String? selectedSupplier;
  @override Widget build(BuildContext context){
    final groups=widget.lines.values.map((x)=>x.supplierId).toSet().toList()..sort((a,b)=>(widget.suppliers[a]??a).compareTo(widget.suppliers[b]??b));
    return Scaffold(appBar:AppBar(title:Text('Sipariş Listesi (${widget.lines.length})')),
      bottomNavigationBar:SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
        Expanded(child:FilledButton.icon(onPressed:widget.lines.isEmpty?null:widget.onExport,icon:const Icon(Icons.file_download_outlined),label:const Text('Sipariş Excel'))),
        const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:widget.lines.isEmpty?null:()async{await widget.onClear();if(mounted)setState((){});},icon:const Icon(Icons.delete_outline),label:const Text('Önceki Siparişi Temizle'))),
      ]))),
      body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(value:selectedSupplier,decoration:const InputDecoration(labelText:'Tedarikçi seç',border:OutlineInputBorder()),
          items:[const DropdownMenuItem<String>(value:null,child:Text('Tüm Tedarikçiler')),...widget.suppliers.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value)))],
          onChanged:(v)=>setState(()=>selectedSupplier=v)),
        const SizedBox(height:8),FilledButton.icon(onPressed:selectedSupplier==null?null:()async{await widget.onSupplierProducts(selectedSupplier!);if(mounted)setState((){});},
          icon:const Icon(Icons.inventory_2_outlined),label:const Text('Tedarikçinin Ürünlerini Göster')),
      ])),Expanded(child:groups.where((id)=>selectedSupplier==null||id==selectedSupplier).isEmpty?const Center(child:Text('Bu tedarikçiye ait sipariş yok')):ListView(children:[for(final supplier in groups.where((id)=>selectedSupplier==null||id==selectedSupplier))...[
        Padding(padding:const EdgeInsets.fromLTRB(16,18,16,8),child:Text(widget.suppliers[supplier]??'Bilinmeyen tedarikçi',style:Theme.of(context).textTheme.titleLarge)),
        for(final l in widget.lines.values.where((x)=>x.supplierId==supplier))ListTile(title:Text(l.name),subtitle:Text('Barkod: ${l.barcode}\nKoličina: ${l.quantity} ${l.unit}'),isThreeLine:true,trailing:Wrap(children:[
          IconButton(icon:const Icon(Icons.edit_outlined),onPressed:()async{await widget.onEdit(l.code);if(mounted)setState((){});}),
          IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{await widget.onDelete(l.code);if(mounted)setState((){});}),
        ])),const Divider(),
      ]]))]));
  }
}
class ProductsPage extends StatefulWidget {
  final Map<String,Product> catalog;
  final Map<String,List<String>> barcodes;
  final Future<void> Function(Product) onOrder;
  final String? supplierId,supplierName;
  final Map<String,String>? productSuppliers;
  const ProductsPage({super.key,required this.catalog,required this.barcodes,required this.onOrder,this.supplierId,this.supplierName,this.productSuppliers});
  @override State<ProductsPage> createState()=>_ProductsPageState();
}
class _ProductsPageState extends State<ProductsPage> {
  String query='',filter='Tümü';
  double limit=5;
  @override Widget build(BuildContext context){
    final products=widget.catalog.values.where((p){
      final q=query.toLowerCase();
      final match=p.name.toLowerCase().contains(q)||p.code.contains(q)||p.barcode.contains(q)||(widget.barcodes[p.code]??[]).any((x)=>x.contains(q));
      final n=double.tryParse(p.stock.replaceAll(',','.'));
      return (widget.supplierId==null||widget.productSuppliers?[p.code]==widget.supplierId)&&match&&(filter=='Tümü'||filter=='Stok 0'&&n!=null&&n<=0||filter=='Az Stok'&&n!=null&&n>0&&n<=limit);
    }).toList()..sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Scaffold(appBar:AppBar(title:Text(widget.supplierId==null?'Tüm Ürünler (${products.length})':'${widget.supplierName??'Tedarikçi'} (${products.length})')),
      body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Naziv, barkod veya ürün kodu',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>query=v)),
        const SizedBox(height:8),Row(children:[Expanded(child:DropdownButtonFormField<String>(value:filter,items:['Tümü','Az Stok','Stok 0'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setState(()=>filter=v??'Tümü'))),const SizedBox(width:12),
          SizedBox(width:112,child:TextFormField(initialValue:'5',keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Az stok ≤'),onChanged:(v)=>setState(()=>limit=double.tryParse(v)??5)))]),
      ])),Expanded(child:ListView.builder(itemCount:products.length,itemBuilder:(ctx,i){final p=products[i];return ListTile(title:Text(p.name),subtitle:Text('ID: ${p.code} • Barkod: ${p.barcode}\nStok: ${p.stock} • ${p.price} KM'),isThreeLine:true,trailing:IconButton(tooltip:'Siparişe Ekle',icon:const Icon(Icons.add_shopping_cart),onPressed:()async{await widget.onOrder(p);if(mounted)setState((){});}));}))]));
  }
}
class IssuesPage extends StatefulWidget {
  final String type;
  final Map<String,Map<String,dynamic>> issues;
  final Future<void> Function() onChanged;
  const IssuesPage({super.key,required this.type,required this.issues,required this.onChanged});
  @override State<IssuesPage> createState()=>_IssuesPageState();
}
class _IssuesPageState extends State<IssuesPage> {
  @override Widget build(BuildContext context){
    final entries=widget.issues.entries.where((e)=>List<String>.from(e.value['types'] as List).contains(widget.type)).toList();
    return Scaffold(appBar:AppBar(title:Text('${widget.type} (${entries.length})')),body:ListView(children:entries.map((e)=>ListTile(title:Text('${e.value['name']}'),subtitle:Text('ID: ${e.key} • Stok: ${e.value['stock']} • Sayılan: ${e.value['count']}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.issues.remove(e.key));await widget.onChanged();}))).toList()));
  }
}

class LabelSettingsPage extends StatefulWidget {
  final Map<String,double> Function(String) current;
  final Future<void> Function(String,Map<String,double>) save;
  const LabelSettingsPage({super.key,required this.current,required this.save});
  @override State<LabelSettingsPage> createState()=>_LabelSettingsPageState();
}
class _LabelSettingsPageState extends State<LabelSettingsPage> {
  String type='a4';
  final fields=<String,TextEditingController>{};
  static const names={'w':'Genişlik (mm)','h':'Yükseklik (mm)','cols':'Sütun','rows':'Satır','left':'Sol kenar (mm)','top':'Üst kenar (mm)','gapX':'Yatay boşluk (mm)','gapY':'Dikey boşluk (mm)','font':'Yazı boyutu','barcodeH':'Barkod yüksekliği (mm)','pageW':'Kağıt genişliği (mm)','pageH':'Kağıt yüksekliği (mm)'};
  @override void initState(){super.initState();_populate();}
  void _populate(){for(final c in fields.values){c.dispose();}fields.clear();for(final e in widget.current(type).entries){fields[e.key]=TextEditingController(text:'${e.value}');}}
  @override void dispose(){for(final c in fields.values){c.dispose();}super.dispose();}
  Future<void> _save()async{
    final values=<String,double>{};
    for(final e in fields.entries){final n=double.tryParse(e.value.text.replaceAll(',','.'));if(n==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${names[e.key]} geçersiz')));return;}values[e.key]=n;}
    if(values['w']!<=0||values['h']!<=0||values['cols']!<1||values['rows']!<1||values['font']!<=0||values['barcodeH']!<=0 || values['left']!<0 || values['top']!<0 || values['gapX']!<0 || values['gapY']!<0 || values['cols']!%1!=0 || values['rows']!%1!=0 || values['left']!+values['cols']!*values['w']!+(values['cols']!-1)*values['gapX']!>values['pageW']! || values['top']!+values['rows']!*values['h']!+(values['rows']!-1)*values['gapY']!>values['pageH']!){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Etiketler kağıda sığmıyor veya ölçüler geçersiz')));return;}
    await widget.save(type,values);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Etiket ayarları kaydedildi')));
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Etiket Baskı Ayarları')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      DropdownButtonFormField<String>(value:type,items:const [DropdownMenuItem(value:'a4',child:Text('A4 • 44 × 36 mm')),DropdownMenuItem(value:'white',child:Text('Küçük Beyaz • 38 × 25 mm')),DropdownMenuItem(value:'color',child:Text('Küçük Renkli • 38 × 25 mm'))],onChanged:(v){if(v!=null)setState((){type=v;_populate();});}),
      const SizedBox(height:12),...names.entries.map((e)=>Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:fields[e.key],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:e.value,border:const OutlineInputBorder())))),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('Ayarları Kaydet')),
    ]));
}

class SupplierDaysPage extends StatefulWidget {
  final Map<String,String> suppliers;
  final Map<String,List<int>> days;
  final Future<void> Function() onSave;
  const SupplierDaysPage({super.key,required this.suppliers,required this.days,required this.onSave});
  @override State<SupplierDaysPage> createState()=>_SupplierDaysPageState();
}
class _SupplierDaysPageState extends State<SupplierDaysPage> {
  static const names=['Pzt','Sal','Çar','Per','Cum','Cmt','Paz'];
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Tedarikçi Sipariş Günleri')),
    body:ListView(children:widget.suppliers.entries.map((e){final selected=widget.days[e.key]??<int>[];return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(e.value,style:Theme.of(context).textTheme.titleMedium),Wrap(spacing:4,children:List.generate(7,(i)=>FilterChip(label:Text(names[i]),selected:selected.contains(i+1),onSelected:(v)async{setState((){final updated=[...selected];if(v){updated.add(i+1);}else{updated.remove(i+1);}widget.days[e.key]=updated;});await widget.onSave();})))])));}).toList()));
}

class RiskPage extends StatelessWidget {
  final Map<String,Product> catalog;
  final Map<String,double> sold;
  final bool verified;
  final Future<void> Function(Product) onOrder;
  const RiskPage({super.key,required this.catalog,required this.sold,required this.verified,required this.onOrder});
  @override Widget build(BuildContext context){
    final top=sold.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    final topIds=top.take(200).map((e)=>e.key).toSet();
    final risk=catalog.values.where((p){final n=double.tryParse(p.stock.replaceAll(',','.'));return n!=null&&n<=(verified&&topIds.contains(p.code)?10:5);}).toList()..sort((a,b)=>(double.tryParse(a.stock.replaceAll(',','.'))??0).compareTo(double.tryParse(b.stock.replaceAll(',','.'))??0));
    return Scaffold(appBar:AppBar(title:Text('Stok Riski (${risk.length})')),
      body:Column(children:[if(!verified)const Padding(padding:EdgeInsets.all(12),child:Text('İlk 200 satış verisi doğrulanmadı; şimdilik tüm ürünlerde 5 adet sınırı kullanılıyor.')),
        Expanded(child:ListView.builder(itemCount:risk.length,itemBuilder:(ctx,i){final p=risk[i];return ListTile(title:Text(p.name),subtitle:Text('Kod: ${p.code} • Barkod: ${p.barcode}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('Stok: ${p.stock}'),IconButton(icon:const Icon(Icons.add_shopping_cart),onPressed:()=>onOrder(p))]));}))]));
  }
}

class LabelQueuePage extends StatefulWidget {
  final Map<String,Product> catalog;
  final Map<String,int> queue;
  final Future<Product> Function(String) refreshProduct;
  final Map<String,double> Function(String) settings;
  final Future<void> Function() onSave;
  const LabelQueuePage({super.key,required this.catalog,required this.queue,required this.refreshProduct,required this.settings,required this.onSave});
  @override State<LabelQueuePage> createState()=>_LabelQueuePageState();
}
class _LabelQueuePageState extends State<LabelQueuePage> {
  final search=TextEditingController();String type='a4';bool busy=false;
  @override void dispose(){search.dispose();super.dispose();}
  void _add(){final v=search.text.trim();Product? p=widget.catalog[v];for(final item in widget.catalog.values){if(item.barcode==v){p=item;break;}}if(p==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ürün bulunamadı')));return;}setState(()=>widget.queue[p!.code]=(widget.queue[p.code]??0)+1);widget.onSave();search.clear();}
  Future<void> _export()async{
    if(widget.queue.isEmpty)return;
    setState(()=>busy=true);
    try{
      final items=<Product>[];
      for(final e in widget.queue.entries){
        // Never silently print stale prices. Stop if current API is unreachable.
        final p=await widget.refreshProduct(e.key);
        for(var i=0;i<e.value;i++)items.add(p);
      }
      final c=widget.settings(type);final mm=PdfPageFormat.mm;
      final w=c['w']!*mm,h=c['h']!*mm;
      final cols=c['cols']!.toInt(),rows=c['rows']!.toInt();
      final pdf=pw.Document();
      for(var offset=0;offset<items.length;offset+=cols*rows){
        final page=items.skip(offset).take(cols*rows).toList();
        pdf.addPage(pw.Page(pageFormat:PdfPageFormat(c['pageW']!*mm,c['pageH']!*mm,marginAll:0),build:(context)=>pw.Stack(children:[
          for(var i=0;i<page.length;i++)pw.Positioned(left:(c['left']!+(i%cols)*(c['w']!+c['gapX']!))*mm,top:(c['top']!+(i~/cols)*(c['h']!+c['gapY']!))*mm,child:pw.SizedBox(width:w,height:h,child:_label(page[i],c))),
        ])));
      }
      final dir=await getTemporaryDirectory();final file=File('${dir.path}/SS_OIL_Etiket_${DateTime.now().millisecondsSinceEpoch}.pdf');await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)],text:'SS OIL • Toplu Etiket PDF');
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('PDF oluşturulamadı. Güncel fiyat alınamadı veya barkod geçersiz: $e')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  pw.Widget _label(Product p,Map<String,double> c){
    final barcode=p.barcode.trim();
    final isEan=RegExp(r'^\d{13}$').hasMatch(barcode);
    final isCode128=barcode.isNotEmpty&&barcode.runes.every((v)=>v>=32&&v<=126);
    final b=isEan?pw.Barcode.ean13():pw.Barcode.code128();
    final font=c['font']!;
    return pw.Padding(padding:const pw.EdgeInsets.all(3),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Text('Šifra: ${p.code}',style:pw.TextStyle(fontSize:font*.75)),
      pw.Expanded(child:pw.Text(p.name,maxLines:2,style:pw.TextStyle(fontSize:font,fontWeight:pw.FontWeight.bold))),
      pw.Align(alignment:pw.Alignment.centerRight,child:pw.Text('${p.price.replaceAll('.',',')} KM',style:pw.TextStyle(fontSize:font*1.5,fontWeight:pw.FontWeight.bold))),
      if(isEan||isCode128)pw.BarcodeWidget(barcode:b,data:barcode,width:double.infinity,height:c['barcodeH']!*PdfPageFormat.mm,drawText:true,textStyle:pw.TextStyle(fontSize:font*.65))
      else pw.Text('Barkod geçersiz: $barcode',style:pw.TextStyle(fontSize:font*.65)),
    ]));
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Etiket Listesi (${widget.queue.values.fold<int>(0,(a,b)=>a+b)})')),
    body:Column(children:[Padding(padding:const EdgeInsets.all(12),child:Column(children:[TextField(controller:search,onSubmitted:(_)=>_add(),decoration:InputDecoration(labelText:'Barkod veya ürün kodu',suffixIcon:IconButton(onPressed:_add,icon:const Icon(Icons.add)),border:const OutlineInputBorder())),const SizedBox(height:8),DropdownButtonFormField<String>(value:type,items:const [DropdownMenuItem(value:'a4',child:Text('A4 • 44 × 36')),DropdownMenuItem(value:'white',child:Text('Küçük Beyaz • 38 × 25')),DropdownMenuItem(value:'color',child:Text('Küçük Renkli • 38 × 25'))],onChanged:(v)=>setState(()=>type=v??type))])),
      Expanded(child:ListView(children:widget.queue.entries.map((e){final p=widget.catalog[e.key];return ListTile(title:Text(p?.name??e.key),subtitle:Text('Kod: ${e.key} • ${p?.price??'?'} KM'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[IconButton(icon:const Icon(Icons.remove),onPressed:(){setState((){if(e.value<=1){widget.queue.remove(e.key);}else{widget.queue[e.key]=e.value-1;}});widget.onSave();}),Text('${e.value}'),IconButton(icon:const Icon(Icons.add),onPressed:(){setState(()=>widget.queue[e.key]=e.value+1);widget.onSave();})]));}).toList())),
      Padding(padding:const EdgeInsets.all(12),child:FilledButton.icon(onPressed:busy||widget.queue.isEmpty?null:_export,icon:const Icon(Icons.picture_as_pdf),label:Text(busy?'Fiyatlar kontrol ediliyor...':'Güncel Fiyatla PDF Oluştur'))),
    ]));
}
