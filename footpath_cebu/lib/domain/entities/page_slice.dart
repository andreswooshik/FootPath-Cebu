class PageSlice<T> {
  const PageSlice({required this.items, this.nextOffset});

  final List<T> items;
  final int? nextOffset;

  bool get hasMore => nextOffset != null;
}
