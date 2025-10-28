class PostInteractionState {
  const PostInteractionState({
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
    this.isLikeLoading = false,
  });

  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isLikeLoading;

  PostInteractionState copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isLikeLoading,
  }) {
    return PostInteractionState(
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      isLikeLoading: isLikeLoading ?? this.isLikeLoading,
    );
  }
}
