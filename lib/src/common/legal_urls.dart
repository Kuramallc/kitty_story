/// Public legal pages the app links to.
///
/// App Store guideline 3.1.2 requires a functional Terms of Use (EULA) link and
/// a Privacy Policy link *in the paywall itself*, not only in the store
/// listing. Missing links are one of the most common subscription rejections.
library;

/// Hosted at kuramallc.com and referenced from the App Store / Play listings.
const String kPrivacyPolicyUrl =
    'https://www.kuramallc.com/home/privacy/kittystory';

/// Kitty Stories' own Terms of Use. Apple requires this link to work from the
/// paywall itself; a dead link fails review.
const String kTermsOfUseUrl = 'https://www.kuramallc.com/home/term/kittystory';

/// Where users can ask for their account to be deleted without installing the
/// app — required separately by Google Play, alongside the in-app flow.
const String kAccountDeletionUrl =
    'https://www.kuramallc.com/home/support/kittystory';
