import '../core/utils/json_utils.dart';

class Paginated<T> {
  const Paginated({
    required this.items,
    required this.page,
    required this.perPage,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int perPage;
  final int total;

  bool get hasMore => page * perPage < total;

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemParser,
  ) {
    final meta = parseMap(json['meta']);
    return Paginated<T>(
      items: parseMapList(json['data']).map(itemParser).toList(),
      page: parseInt(meta['page']) ?? 1,
      perPage: parseInt(meta['per_page']) ?? 20,
      total: parseInt(meta['total']) ?? 0,
    );
  }

  static Paginated<T> empty<T>() {
    return Paginated<T>(items: const [], page: 1, perPage: 20, total: 0);
  }
}
