import SwiftUI
import WebAdViewSDK

//MARK: Homepage view
struct HomepageView: View {
    @EnvironmentObject var debugSettings: DebugSettings
    @State private var showConsentOnAppear = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header Banner Ad
                    WebAdView(adUnitId: "div-gpt-ad-mobile_1", initialHeight: 320, minHeight: 320, maxHeight: 320)
                        .customTargeting("section", "homepage")
                        .customTargeting("tags", ["breaking", "featured", "local"])
                        .showAdLabel(true, text: "annonce")
                        // Honest measurement is the SDK default — no modifier
                        // needed. Google's own viewable verdict should fire
                        // ~when the native engine latches.
                        .onActiveViewImpression { slotId in
                            SNLog.log("[DEMO] 🟢 GPT ActiveView viewable impression (honest default): \(slotId)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    
                    // Featured Article Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("BREAKING NEWS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        
                        NavigationLink(destination: Article1View()) {
                            VStack(alignment: .leading, spacing: 8) {
                                // Featured image placeholder
                                Image(systemName: "photo.fill")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 200)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gray.opacity(0.3))
                                    .foregroundColor(.gray.opacity(0.6))
                                    .clipped()
                                    .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Major Tech Breakthrough Changes Everything We Know About Mobile Advertising")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    
                                    Text("Industry experts are calling this the most significant advancement in digital advertising technology in over a decade. The implications could reshape how we interact with mobile content...")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                    
                                    HStack {
                                        Text("Tech News")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text("2 hours ago")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                    
                    WebAdView(adUnitId: "div-gpt-ad-mobile_2")
                        .showAdLabel(true, text: "annonce")
                        // Demo of the viewability API: a host callback that
                        // fires when the impression latches (≥50% for 1s,
                        // the IAB/MRC display standard — the SDK's only mode).
                        .onViewabilityChange { update in
                            if update.becameViewable {
                                SNLog.log("[DEMO] \(update.adUnitId) counted as a viewable impression (\(update.mode.rawValue))")
                            }
                        }
                        // Loads below the fold with honest measurement (SDK
                        // default): GPT's viewable event must stay silent until
                        // the ad is actually scrolled into view.
                        .onActiveViewImpression { slotId in
                            SNLog.log("[DEMO] 🟢 GPT ActiveView viewable impression (honest default): \(slotId)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    // Latest News Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Latest News")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            Button("View All") {
                                // Action for view all
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        
                        // News articles grid
                        LazyVStack(spacing: 16) {
                            // Article 2 Preview
                            NavigationLink(destination: Article2View()) {
                                ArticleRowView(
                                    title: "Climate Summit Reaches Historic Agreement on Carbon Emissions",
                                    summary: "World leaders unite on ambitious new targets that could transform global energy policies...",
                                    category: "Environment",
                                    timeAgo: "4 hours ago",
                                    imageSystemName: "leaf.fill"
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Article 3 Preview
                            NavigationLink(destination: Article3View()) {
                                ArticleRowView(
                                    title: "Space Mission Discovers Potentially Habitable Exoplanet",
                                    summary: "Scientists celebrate groundbreaking discovery that could change our understanding of life beyond Earth...",
                                    category: "Science",
                                    timeAgo: "6 hours ago",
                                    imageSystemName: "globe.americas.fill"
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Banner Ad between articles
                            WebAdView(adUnitId: "div-gpt-ad-mobile_3")
                                .showAdLabel(true, text: "annonce")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            
                            // More article previews
                            NavigationLink(destination: Article1View()) {
                                ArticleRowView(
                                    title: "Economic Markets Show Strong Recovery Signs",
                                    summary: "Financial analysts report positive trends across multiple sectors as confidence returns...",
                                    category: "Business",
                                    timeAgo: "8 hours ago",
                                    imageSystemName: "chart.line.uptrend.xyaxis"
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            NavigationLink(destination: Article2View()) {
                                ArticleRowView(
                                    title: "Revolutionary Medical Treatment Shows Promise",
                                    summary: "Clinical trials demonstrate remarkable success rates for new therapy approach...",
                                    category: "Health",
                                    timeAgo: "12 hours ago",
                                    imageSystemName: "heart.fill"
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            NavigationLink(destination: Article3View()) {
                                ArticleRowView(
                                    title: "Artificial Intelligence Breakthrough in Language Processing",
                                    summary: "New AI model demonstrates unprecedented understanding of human communication...",
                                    category: "Technology",
                                    timeAgo: "1 day ago",
                                    imageSystemName: "brain.head.profile"
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                    
                    // Footer Ad — plain WebAdView: honest measurement by default
                    WebAdView(adUnitId: "div-gpt-ad-mobile_4")
                        .showAdLabel(true, text: "annonce")
                        .onActiveViewImpression { slotId in
                            SNLog.log("[DEMO] 🟢 GPT ActiveView viewable impression (honest default): \(slotId)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    
                    // Settings and Preferences
                    VStack(spacing: 12) {
                        Button(action: {
                            WebAdViewSDK.showConsentPreferences()
                        }) {
                            HStack {
                                Image(systemName: "shield.checkerboard")
                                Text("Privacy Settings")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .foregroundColor(.primary)
                        
                        HStack {
                            Text("© 2025 News Demo App")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .lazyLoadAd(true) // Apply lazy loading to the ScrollView itself
            .navigationTitle("NewsHub")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { debugSettings.isDebugEnabled.toggle() }) {
                        Image(systemName: debugSettings.isDebugEnabled ? "ladybug.fill" : "ladybug")
                            .foregroundColor(debugSettings.isDebugEnabled ? .red : .primary)
                            .accessibilityLabel("Toggle Debug Mode")
                    }
                }
            }
        }
        .background(DidomiWrapper()) // Ensures Didomi has a valid UIViewController for UI
    }
}

// MARK: - Article Row View Component
struct ArticleRowView: View {
    let title: String
    let summary: String
    let category: String
    let timeAgo: String
    let imageSystemName: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Article image placeholder
            Image(systemName: imageSystemName)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.gray.opacity(0.6))
                .cornerRadius(8)
                .clipped()
            
            // Article content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(timeAgo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}


//MARK: Article views
struct Article1View: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Article header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("TECH NEWS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        Spacer()
                        Text("2 hours ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Major Tech Breakthrough Changes Everything We Know About Mobile Advertising")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                    
                    Text("By Sarah Johnson • Tech Reporter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                
                // Featured image
                Image(systemName: "smartphone")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.gray.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                
                // Top banner ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_1", initialHeight: 320, minHeight: 320, maxHeight: 320)
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                
                // Article content - Part 1
                VStack(alignment: .leading, spacing: 16) {
                    Text("In a groundbreaking development that promises to reshape the mobile advertising landscape, researchers at leading technology companies have unveiled revolutionary techniques that could transform how users interact with digital content on their devices.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The new approach, which has been in development for over three years, addresses longstanding concerns about user experience while maintaining the economic viability of free, ad-supported mobile applications and websites.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The breakthrough emerged from a collaboration between Silicon Valley giants, European privacy advocates, and academic institutions worldwide. Dr. Rebecca Thomson, lead researcher at the Digital Advertising Research Consortium, explained that the project began in 2021 when user complaints about intrusive advertising reached an all-time high.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"We realized that the traditional model of advertising was fundamentally broken,\" Dr. Thomson said. \"Users were becoming increasingly frustrated with ads that felt invasive, while advertisers were struggling to reach their intended audiences effectively. We needed a complete paradigm shift.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Technical Innovation")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("The core innovation lies in what researchers call 'contextual intelligence' – a sophisticated system that analyzes user behavior patterns without storing personal data. Instead of tracking individual users across websites and apps, the technology creates anonymous behavioral clusters that help advertisers reach relevant audiences while preserving privacy.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("This approach uses advanced machine learning algorithms that operate entirely on the user's device, eliminating the need for data to be transmitted to external servers. The result is a system that is both more private and more responsive than current advertising technologies.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Key Benefits Include:")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Improved user privacy through advanced consent management")
                        }
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Enhanced ad relevance without compromising personal data")
                        }
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Faster loading times and reduced battery consumption")
                        }
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Seamless integration with existing mobile frameworks")
                        }
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Real-time performance optimization based on device capabilities")
                        }
                        HStack(alignment: .top) {
                            Text("•")
                                .fontWeight(.bold)
                            Text("Cross-platform compatibility for iOS, Android, and web applications")
                        }
                    }
                    .font(.body)
                }
                .padding(.horizontal, 16)
                
                // Mid-article ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_2")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Industry Impact")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Leading technology executives are praising the innovation, with many predicting widespread adoption across the industry within the next 18 months. The breakthrough addresses critical challenges that have plagued mobile advertising for years.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The technology's development required overcoming significant technical hurdles. Traditional advertising systems rely heavily on third-party cookies and cross-site tracking, which have become increasingly problematic due to privacy regulations like GDPR and CCPA. The new approach eliminates these dependencies entirely.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"This represents the most significant advancement in mobile advertising technology we've seen in over a decade,\" said Maria Rodriguez, Chief Technology Officer at a prominent digital advertising platform. \"The potential implications for both publishers and users are extraordinary.\"")
                        .font(.body)
                        .italic()
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("Performance Metrics")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("Early testing has shown remarkable improvements across all key performance indicators. Ad load times have decreased by an average of 67%, while click-through rates have increased by 43%. Perhaps most importantly, user satisfaction scores have improved by 89% in test environments.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Beta testing involved over 50,000 users across different demographics and geographic regions. The results were consistently positive, with users reporting that ads felt more relevant and less intrusive than traditional advertising formats.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"The difference is night and day,\" said Jennifer Walsh, a beta tester from Portland. \"I actually find myself engaging with ads now because they're genuinely useful and don't interrupt my browsing experience.\"")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Another mid-article ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_3")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Market Implications")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Financial analysts predict the technology could reshape the entire digital advertising ecosystem, which currently represents a $500 billion global market. Companies that adopt the new approach early are expected to gain significant competitive advantages.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Stock prices for advertising technology companies have already begun reflecting investor optimism about the breakthrough. AdTech Corp saw its shares rise 23% following the announcement, while traditional advertising giants are scrambling to adapt their strategies.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"This isn't just an incremental improvement – it's a fundamental shift in how digital advertising works,\" explained Dr. Michael Chang, a market analyst specializing in advertising technology. \"Companies that fail to adapt risk being left behind.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Global Adoption Timeline")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("The technology is expected to begin rolling out to select partners in the coming months, with broader availability anticipated by the end of the year. Industry analysts suggest this could mark a turning point in how mobile content is monetized and consumed.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Major smartphone manufacturers are already expressing interest in integrating the technology at the operating system level. Apple and Google have both indicated they are \"closely monitoring\" the development, though neither company has made official commitments.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The European Union has praised the privacy-focused approach, with some officials suggesting it could become a model for future advertising regulations. Similar positive responses have come from privacy advocates in the United States and Canada.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Technical Implementation")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("For developers, implementing the new technology requires minimal changes to existing codebases. The system is designed to work as a drop-in replacement for current advertising SDKs, with comprehensive documentation and migration tools already available.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"We've prioritized ease of adoption,\" said Dr. Thomson. \"Publishers shouldn't have to completely rebuild their applications to benefit from this technology. The transition should be as seamless as possible.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The development team has also created extensive testing frameworks to help publishers optimize their ad implementations. These tools provide real-time feedback on performance metrics and user engagement patterns.")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Final article ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_4")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Looking Forward")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("As the advertising industry prepares for this significant shift, attention is turning to the long-term implications for digital content creation and consumption. Publishers are already reporting increased user engagement and longer session times in test environments.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"This technology doesn't just make ads better – it makes the entire digital experience more enjoyable,\" concluded Rodriguez. \"When advertising works harmoniously with content instead of competing with it, everyone benefits.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The research team continues to refine the technology, with plans to release additional features throughout 2025. These include enhanced personalization capabilities and improved support for emerging content formats like augmented reality and interactive media.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Industry experts agree that this breakthrough represents just the beginning of a new era in digital advertising – one that prioritizes user experience without sacrificing the economic models that support free content on the internet.")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Social sharing section
                HStack {
                    Text("Share this article:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                        Button(action: {}) {
                            Image(systemName: "heart")
                                .foregroundColor(.red)
                        }
                        Button(action: {}) {
                            Image(systemName: "bookmark")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .navigationTitle("Article")
            .navigationBarTitleDisplayMode(.inline)
        }
        .lazyLoadAd(true)
    }
}

struct Article2View: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Article header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ENVIRONMENT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        Spacer()
                        Text("4 hours ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Climate Summit Reaches Historic Agreement on Carbon Emissions")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                    
                    Text("By Michael Chen • Environmental Correspondent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                
                // Featured image
                Image(systemName: "leaf.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                
                // Article content with ads interspersed
                VStack(alignment: .leading, spacing: 16) {
                    Text("World leaders have reached a unprecedented consensus on ambitious carbon emission reduction targets at this year's Global Climate Summit, marking what many consider the most significant environmental agreement since the Paris Climate Accord.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The agreement, signed by representatives from 195 countries, establishes binding commitments to reduce global carbon emissions by 60% by 2035, with interim targets of 30% by 2030.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The negotiations, which lasted 72 hours straight in the final phase, were described by veteran diplomats as the most intense environmental discussions in decades. Several times the talks appeared to be on the verge of collapse, only to be saved by last-minute interventions from key world leaders.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"There were moments when we thought we wouldn't reach any agreement at all,\" said Ambassador Clara Petersen, who led the Nordic delegation. \"But the scientific evidence was so compelling that everyone understood we had no choice but to act decisively.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The breakthrough came when developing nations agreed to accelerated emission reduction timelines in exchange for unprecedented technology transfer commitments from industrialized countries. This arrangement addresses one of the major sticking points that has historically prevented global climate consensus.")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Top banner ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_1", initialHeight: 320, minHeight: 320, maxHeight: 320)
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Summit Highlights")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Renewable Energy Transition")
                                    .fontWeight(.semibold)
                                Text("Commitment to 80% renewable energy by 2040")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Carbon Pricing Mechanism")
                                    .fontWeight(.semibold)
                                Text("Global carbon tax framework implementation")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Technology Sharing Initiative")
                                    .fontWeight(.semibold)
                                Text("Open access to clean technology patents")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Mid-article ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_2")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Scientific Foundation")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("The agreement is built upon the latest climate science, including alarming new data from the Intergovernmental Panel on Climate Change showing that global temperatures could rise by 2.8°C by 2100 without immediate action. This projection prompted many previously hesitant nations to join the consensus.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Dr. Rajesh Sharma, lead climate scientist at the International Climate Monitoring Center, presented data showing that current emission levels are tracking toward the worst-case scenarios outlined in previous climate models. His presentation was described as a \"wake-up call\" that galvanized negotiators.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"The window for limiting warming to 1.5°C is rapidly closing,\" Dr. Sharma explained during the summit. \"Without the commitments made here today, we would be looking at catastrophic climate impacts within our children's lifetimes.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Expert Analysis")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Dr. Elena Vasquez, Director of the International Climate Research Institute, described the agreement as \"a watershed moment in global environmental policy.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"What makes this agreement different is its enforceability mechanisms and the unprecedented level of international cooperation we're seeing,\" Dr. Vasquez explained. \"For the first time, we have binding commitments with real consequences for non-compliance.\"")
                        .font(.body)
                        .italic()
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("The agreement includes provisions for annual progress reviews, with countries required to submit detailed emission reduction reports and face potential economic penalties for falling short of targets.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Economic Transformation")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("The climate agreement is expected to trigger the largest economic transformation since the Industrial Revolution. Economists estimate that implementing the targets will require global investments of $4.2 trillion annually through 2035.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("However, the same economists note that the cost of inaction would be far higher. Climate damage is already costing the global economy approximately $23 trillion annually through extreme weather events, crop failures, and infrastructure damage.")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Another mid-article ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_3")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Industry Response")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Major corporations have begun announcing massive clean energy investments within hours of the agreement's signing. Tech giant MegaCorp pledged $50 billion toward renewable energy infrastructure, while automotive manufacturer EcoDrive committed to ending all internal combustion engine production by 2030.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"This agreement provides the certainty businesses need to make long-term investments in clean technology,\" said Robert Chen, CEO of GreenTech Industries. \"When you know the rules of the game, you can plan accordingly.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The renewable energy sector has seen particularly dramatic responses. Solar panel manufacturer SunPower announced plans to triple production capacity, while wind energy company WindForce revealed a $30 billion expansion program.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Regional Implementation")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("Different regions will face varying challenges in meeting the new targets. European nations, already leaders in renewable energy adoption, expressed confidence about meeting their commitments ahead of schedule. Meanwhile, developing economies in Asia and Africa will receive substantial financial and technical support.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("China, the world's largest emitter, surprised many by committing to even more aggressive targets than required. President Liu Wei announced that China would aim for carbon neutrality by 2055, five years earlier than previously planned.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"China recognizes that climate leadership is essential for global stability and economic prosperity,\" President Liu stated. \"We are prepared to lead by example.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Looking Ahead")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 8)
                    
                    Text("Implementation begins immediately, with the first major milestone set for 2027. Industry leaders are already announcing substantial investments in clean technology and renewable energy infrastructure in response to the new framework.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The agreement also establishes a new international body, the Global Climate Implementation Authority, which will monitor progress and coordinate technology transfer between nations. This organization will be funded by developed countries and will have unprecedented powers to enforce compliance.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Environmental groups, while celebrating the agreement, emphasized that implementation will be the true test of its success. \"Signing the agreement was the easy part,\" said Maria Santos of the Global Environmental Alliance. \"Now comes the hard work of actually reducing emissions.\"")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Related articles section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Related Articles")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 8) {
                        HStack {
                            Text("• Renewable Energy Stocks Surge Following Climate Agreement")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        HStack {
                            Text("• Tech Giants Announce $500B Clean Energy Investment")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                        HStack {
                            Text("• How the New Carbon Tax Will Affect Consumers")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .navigationTitle("Environment")
            .navigationBarTitleDisplayMode(.inline)
        }
        .lazyLoadAd(true)
    }
}

struct Article3View: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Article header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SCIENCE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
                        Spacer()
                        Text("6 hours ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Space Mission Discovers Potentially Habitable Exoplanet")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                    
                    Text("By Dr. Amanda Foster • Space Science Editor")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                
                // Featured image
                Image(systemName: "globe.americas.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.2))
                    .foregroundColor(.purple.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                
                // Article content - Part 1
                VStack(alignment: .leading, spacing: 16) {
                    Text("In a discovery that could fundamentally change our understanding of life beyond Earth, the Kepler Space Observatory has identified an exoplanet with conditions remarkably similar to our own planet, located just 22 light-years away in the constellation Lyra.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The planet, designated Kepler-442c, orbits within the habitable zone of its host star and shows strong indicators of having liquid water on its surface—a key requirement for life as we know it.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The discovery was made possible by a new analysis technique that combines data from multiple space telescopes, including Kepler, the Transiting Exoplanet Survey Satellite (TESS), and ground-based observatories around the world. This collaborative approach has revolutionized our ability to detect and characterize potentially habitable worlds.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Dr. Sarah Martinez, principal investigator on the project, described the moment of discovery: \"When we first saw the spectroscopic data, we had to run the analysis three times to make sure we weren't making an error. The atmospheric composition was unlike anything we'd seen before – it was almost too good to be true.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The team spent eight months verifying their findings through independent observations and peer review. The results were consistent across all measurement techniques, providing unprecedented confidence in the planet's habitability potential.")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Top banner ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_1", initialHeight: 320, minHeight: 320, maxHeight: 320)
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Discovery Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        InfoRowView(icon: "ruler", title: "Planet Size", value: "1.34 × Earth")
                        InfoRowView(icon: "thermometer", title: "Surface Temperature", value: "15°C average")
                        InfoRowView(icon: "clock", title: "Orbital Period", value: "267 Earth days")
                        InfoRowView(icon: "location", title: "Distance", value: "22.1 light-years")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                
                // Mid-article ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_2")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Atmospheric Analysis")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("What makes Kepler-442c particularly extraordinary is its atmospheric composition. Advanced spectroscopic analysis has revealed the presence of water vapor, oxygen, methane, and phosphine – a combination that, on Earth, is almost exclusively associated with biological processes.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"The detection of phosphine was especially surprising,\" explained Dr. Robert Kim, an atmospheric physicist at the Space Science Institute. \"On Earth, phosphine is produced almost entirely by biological organisms. Finding it in an exoplanet's atmosphere is like finding a smoking gun for potential life.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The atmospheric oxygen levels on Kepler-442c are approximately 18% – remarkably close to Earth's 21%. This suggests active oxygen production, possibly through photosynthesis or similar biological processes.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Scientific Significance")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\"This discovery represents one of the most Earth-like planets we've ever found,\" said Dr. James Wilson, lead researcher on the Kepler mission team. \"The combination of its size, temperature, and orbital characteristics make it an exceptional candidate for hosting life.\"")
                        .font(.body)
                        .italic()
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("The planet's host star, Kepler-442, is a K-type star slightly smaller and cooler than our Sun, providing stable conditions that could have allowed life to evolve over billions of years. K-type stars are increasingly recognized as potentially ideal hosts for life because they have longer lifespans than Sun-like stars and emit less harmful radiation.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Computer models suggest that Kepler-442c has maintained stable surface temperatures for at least 3.2 billion years – more than enough time for complex life to evolve, assuming it began with simple organisms similar to Earth's earliest life forms.")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Another ad placement
                WebAdView(adUnitId: "div-gpt-ad-mobile_3")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Geological Indicators")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Beyond atmospheric analysis, researchers have detected what appear to be seasonal variations in the planet's spectral signature, suggesting active weather patterns and possibly even seasonal changes similar to Earth's. This finding adds another layer of evidence supporting the planet's habitability.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Thermal imaging has revealed large bodies of liquid on the planet's surface, with temperatures and reflectivity patterns consistent with water oceans. These oceans appear to cover approximately 68% of the planet's surface – slightly less than Earth's 71%.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"The presence of large oceans is crucial,\" noted Dr. Lisa Chen, a planetary geologist. \"Oceans moderate temperature, provide a stable environment for life to develop, and enable global circulation patterns that distribute nutrients and heat around the planet.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("International Collaboration")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 12)
                    
                    Text("The discovery represents a triumph of international scientific collaboration. Teams from NASA, ESA, the Japanese Space Agency, and the Indian Space Research Organisation all contributed data and analysis. This cooperative approach allowed for unprecedented precision in characterizing the distant world.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"No single space agency could have made this discovery alone,\" emphasized Dr. Martinez. \"It required the combined expertise and resources of the global scientific community. This is what space exploration should look like in the 21st century.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Next Steps")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("The James Webb Space Telescope will now turn its attention to Kepler-442c for more detailed observations. Scientists hope to analyze the planet's atmosphere more precisely and search for potential biosignatures—chemical indicators that could suggest the presence of life.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Additionally, the upcoming Extremely Large Telescope, currently under construction in Chile, will be able to directly image the planet and potentially detect seasonal changes in its atmosphere and surface features when it becomes operational in 2028.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"While we can't yet definitively say there is life on Kepler-442c, all the conditions appear to be right,\" explained Dr. Sarah Martinez, an astrobiologist at the Institute for Extraterrestrial Research. \"This discovery brings us one step closer to answering one of humanity's most profound questions: Are we alone in the universe?\"")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Final ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_4")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Technological Implications")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("The discovery has prompted renewed interest in interstellar travel concepts. While 22 light-years remains an enormous distance by current technological standards, it's relatively close in astronomical terms. Several organizations are already updating their long-term space exploration roadmaps.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Breakthrough Starshot, a project aimed at developing tiny, light-propelled spacecraft, has announced that Kepler-442c will be added to their target list. These miniature probes, if successful, could reach the planet within 80-100 years and transmit basic data back to Earth.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"This discovery gives us a concrete target for future interstellar missions,\" said Dr. Peter Williams, director of the Interstellar Research Initiative. \"Having a specific, potentially habitable world to aim for changes everything about how we plan for the future of space exploration.\"")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Future Missions")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Plans are already underway for more advanced space missions that could provide even more detailed information about potentially habitable exoplanets. The upcoming Habitable Worlds Observatory, scheduled for launch in 2035, will have the capability to directly image Earth-like planets and analyze their atmospheres in unprecedented detail.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("This discovery also reinforces the importance of continued investment in space exploration and the search for extraterrestrial life, which could have profound implications for our understanding of biology, chemistry, and our place in the cosmos.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("The European Space Agency has announced plans for a dedicated exoplanet characterization mission, tentatively called 'New Worlds,' which would focus specifically on studying the most promising potentially habitable worlds identified by current and future surveys.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("\"Kepler-442c represents hope,\" concluded Dr. Wilson. \"Hope that life is not unique to Earth, hope that we might one day find kindred spirits among the stars, and hope that humanity's future extends far beyond our own solar system.\"")
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 16)
                
                // Bottom ad
                WebAdView(adUnitId: "div-gpt-ad-mobile_5")
                    .showAdLabel(true, text: "artikel forsætter efter annonce")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                
                Spacer()
            }
            .navigationTitle("Science")
            .navigationBarTitleDisplayMode(.inline)
        }
        .lazyLoadAd(true)
    }
}

// MARK: - Supporting Views
struct InfoRowView: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.purple)
                .frame(width: 20)
            Text(title)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
