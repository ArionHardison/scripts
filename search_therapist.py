import requests
from bs4 import BeautifulSoup
import re
import time
from typing import Dict, List, Optional, Tuple
import os
from fake_useragent import UserAgent
from urllib.parse import quote
import random
import json
import concurrent.futures
from concurrent.futures import ThreadPoolExecutor
import threading
from queue import Queue
import tqdm

def load_data(file_path: str) -> dict:
    """Load data from JSON file."""
    try:
        with open(file_path, 'r') as file:
            return json.load(file)
    except FileNotFoundError:
        print(f"Error: {file_path} not found")
        return {}

def get_google_search_results(query: str, max_results: int = 5) -> List[str]:
    """
    Get search results from Google
    """
    ua = UserAgent()
    encoded_query = quote(query)
    urls = []
    
    try:
        headers = {
            'User-Agent': ua.random,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1'
        }
        
        url = f"https://www.google.com/search?q={encoded_query}"
        response = requests.get(url, headers=headers, timeout=10)
        
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, 'html.parser')
            # Google specific search for result links
            for div in soup.find_all('div', class_='yuRUbf'):  # Google's link container class
                link = div.find('a')
                if link:
                    href = link.get('href', '')
                    if href.startswith('http') and not any(x in href.lower() for x in ['google.com', 'facebook.com', 'twitter.com']):
                        urls.append(href)
                        if len(urls) >= max_results:
                            break
        
        return urls[:max_results]
    
    except Exception as e:
        print(f"Google search error: {e}")
        return []

def get_bing_search_results(query: str, max_results: int = 5) -> List[str]:
    """
    Get search results from Bing
    """
    ua = UserAgent()
    encoded_query = quote(query)
    urls = []
    
    try:
        headers = {
            'User-Agent': ua.random,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'DNT': '1',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1'
        }
        
        url = f"https://www.bing.com/search?q={encoded_query}"
        response = requests.get(url, headers=headers, timeout=10)
        
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, 'html.parser')
            links = soup.find_all('a')
            
            for link in links:
                href = link.get('href', '')
                if href.startswith('http') and not any(x in href.lower() for x in ['bing.com', 'microsoft.com', 'facebook.com', 'twitter.com']):
                    urls.append(href)
                    if len(urls) >= max_results:
                        break
        
        return urls[:max_results]
    
    except Exception as e:
        print(f"Bing search error: {e}")
        return []

def process_url_for_contact_info(url: str) -> Dict[str, List[str]]:
    """Process a single URL to extract contact information."""
    results = {
        'emails': [],
        'phones': [],
        'websites': [url]
    }
    
    try:
        print(f"  Accessing: {url}")
        ua = UserAgent()
        headers = {'User-Agent': ua.random}
        response = requests.get(url, headers=headers, timeout=10)
        
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, 'html.parser')
            text = soup.get_text()
            
            # Extract emails
            emails = re.findall(r'[\w\.-]+@[\w\.-]+\.\w+', text)
            if emails:
                print(f"    ✉️  Found {len(emails)} email(s)")
                results['emails'].extend(emails)
            
            # Extract phones
            phones = re.findall(r'\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}', text)
            if phones:
                print(f"    📞 Found {len(phones)} phone number(s)")
                results['phones'].extend(phones)
        else:
            print(f"    ⚠️  Failed to access URL (Status: {response.status_code})")
    
    except Exception as e:
        print(f"    ❌ Error processing URL: {str(e)}")
    
    return results

def search_therapist(name: str, location: Optional[str] = None) -> Dict[str, List[str]]:
    """
    Search for therapist information and extract contact details using both Google and Bing
    """
    results = {
        'emails': [],
        'phones': [],
        'websites': [],
        'addresses': []
    }
    
    query = f"{name} therapist contact information"
    if location:
        query += f" {location}"
    
    try:
        # Get URLs from both Google and Bing
        print("Searching Google...")
        google_urls = get_google_search_results(query)
        time.sleep(random.uniform(2, 4))  # Delay between search engines
        
        print("Searching Bing...")
        bing_urls = get_bing_search_results(query)
        
        # Combine and deduplicate URLs
        urls = list(set(google_urls + bing_urls))
        print(f"Found {len(urls)} unique URLs to process")
        
        ua = UserAgent()
        
        for url in urls:
            try:
                print(f"\nProcessing: {url}")
                time.sleep(random.uniform(1, 3))
                
                headers = {'User-Agent': ua.random}
                response = requests.get(url, headers=headers, timeout=10)
                
                if response.status_code == 200:
                    soup = BeautifulSoup(response.text, 'html.parser')
                    text = soup.get_text()
                    
                    # Search for emails with more patterns
                    emails = re.findall(r'[\w\.-]+@[\w\.-]+\.\w+', text)
                    # Additional email pattern for "email:" or "contact:" followed by address
                    email_patterns = re.findall(r'(?:email|contact|e-mail):\s*([\w\.-]+@[\w\.-]+\.\w+)', text, re.I)
                    emails.extend(email_patterns)
                    
                    # Search for phone numbers (various formats)
                    phones = re.findall(r'\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}', text)
                    # Additional phone patterns
                    phone_patterns = re.findall(r'(?:phone|tel|call):\s*(\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4})', text, re.I)
                    phones.extend(phone_patterns)
                    
                    # Add URL to websites
                    results['websites'].append(url)
                    
                    # Update results
                    results['emails'].extend(emails)
                    results['phones'].extend(phones)
                    
                    # Save raw HTML for debugging
                    save_debug_html(name, url, response.text)
                    
                    print(f"Found {len(emails)} emails and {len(phones)} phone numbers")
                
            except Exception as e:
                print(f"Error processing URL {url}: {e}")
                continue
        
        # Remove duplicates and clean results
        results = {k: list(set(v)) for k, v in results.items()}
        
        return results
    
    except Exception as e:
        print(f"Error searching for {name}: {e}")
        return results

def save_debug_html(name: str, url: str, html: str):
    """Save HTML content for debugging purposes."""
    try:
        debug_dir = "debug_html"
        os.makedirs(debug_dir, exist_ok=True)
        
        safe_name = "".join(c if c.isalnum() else "_" for c in name)
        safe_url = "".join(c if c.isalnum() else "_" for c in url[:30])
        filename = f"{debug_dir}/{safe_name}_{safe_url}.html"
        
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(html)
    except Exception as e:
        print(f"Error saving debug HTML: {e}")

def score_contact_info(contact: str, therapist: Dict, contact_type: str) -> float:
    """
    Score how likely a contact detail belongs to the therapist.
    Returns a score between 0 and 1, where 1 is most likely.
    """
    score = 0.0
    name = therapist.get('name', '').lower()
    location = therapist.get('location', '').lower()
    specialties = therapist.get('specialties', [])
    practice_name = therapist.get('practice_name', '').lower()
    
    if contact_type == 'email':
        email_lower = contact.lower()
        
        # Check if therapist name appears in email
        name_parts = name.split()
        for part in name_parts:
            if len(part) > 2 and part in email_lower:  # Avoid matching short names
                score += 0.4
                break
        
        # Check for professional domains
        if any(domain in email_lower for domain in ['.edu', 'psychologist', 'therapy', 'counseling', 'wellness']):
            score += 0.2
        
        # Check if practice name appears in email
        if practice_name and practice_name in email_lower:
            score += 0.3
        
        # Penalize generic emails
        if any(generic in email_lower for generic in ['info@', 'contact@', 'admin@', 'office@']):
            score -= 0.2
            
    elif contact_type == 'phone':
        # Remove non-numeric characters for comparison
        clean_phone = ''.join(filter(str.isdigit, contact))
        existing_phone = therapist.get('phone', '')
        if existing_phone:
            existing_clean = ''.join(filter(str.isdigit, existing_phone))
            
            # If area codes match, likely in same region
            if clean_phone[:3] == existing_clean[:3]:
                score += 0.3
        
        # Check if phone appears in original data
        if contact in str(therapist):
            score += 0.5
            
    elif contact_type == 'website':
        website_lower = contact.lower()
        
        # Check if therapist name appears in URL
        name_parts = name.split()
        for part in name_parts:
            if len(part) > 2 and part in website_lower:
                score += 0.4
                break
        
        # Check if practice name appears in URL
        if practice_name and practice_name in website_lower:
            score += 0.3
        
        # Check for therapy-related terms
        if any(term in website_lower for term in ['therapy', 'counseling', 'psychologist', 'wellness']):
            score += 0.2
        
        # Prefer professional domains
        if website_lower.endswith(('.com', '.org', '.net')):
            score += 0.1
            
        # Penalize social media and directory sites
        if any(site in website_lower for site in ['facebook', 'linkedin', 'psychology.com', 'healthgrades']):
            score -= 0.2
    
    # Location-based scoring
    if location:
        location_parts = location.split()
        if any(part.lower() in contact.lower() for part in location_parts if len(part) > 2):
            score += 0.1
    
    return min(max(score, 0.0), 1.0)  # Ensure score is between 0 and 1

def select_best_contact_info(contacts: List[str], therapist: Dict, contact_type: str) -> Optional[str]:
    """Select the most likely correct contact information."""
    if not contacts:
        return None
        
    # Score each contact
    scored_contacts = [(contact, score_contact_info(contact, therapist, contact_type)) 
                      for contact in contacts]
    
    # Sort by score in descending order
    scored_contacts.sort(key=lambda x: x[1], reverse=True)
    
    # Print scoring results for debugging
    print(f"\n   {contact_type.title()} scoring results:")
    for contact, score in scored_contacts:
        print(f"    • {contact}: {score:.2f}")
    
    # Return the highest-scored contact if it meets minimum threshold
    if scored_contacts and scored_contacts[0][1] >= 0.3:  # Minimum confidence threshold
        return scored_contacts[0][0]
    return None

def update_therapist_data(therapist: Dict, search_results: Dict) -> Dict:
    """Update therapist data with search results."""
    updated_therapist = therapist.copy()
    changes_made = []
    
    # Select best email
    if search_results['emails'] and not updated_therapist.get('email'):
        best_email = select_best_contact_info(search_results['emails'], therapist, 'email')
        if best_email:
            updated_therapist['email'] = best_email
            changes_made.append(f"Added email: {best_email}")
    
    # Select best phone
    if search_results['phones'] and not updated_therapist.get('phone'):
        best_phone = select_best_contact_info(search_results['phones'], therapist, 'phone')
        if best_phone:
            updated_therapist['phone'] = best_phone
            changes_made.append(f"Added phone: {best_phone}")
    
    # Select best website
    if search_results['websites'] and not updated_therapist.get('website'):
        best_website = select_best_contact_info(search_results['websites'], therapist, 'website')
        if best_website:
            updated_therapist['website'] = best_website
            changes_made.append(f"Added website: {best_website}")
    
    # Store all found data in debug field
    if any(search_results.values()):
        updated_therapist['debug_search_results'] = search_results
    
    return updated_therapist, changes_made

# Add a thread-safe print function
print_lock = threading.Lock()
def safe_print(*args, **kwargs):
    with print_lock:
        print(*args, **kwargs)

def process_single_therapist(therapist: Dict, index: int, total: int) -> Tuple[int, Dict, List[str]]:
    """Process a single therapist with thread-safe logging."""
    name = therapist.get('name', 'Unknown')
    location = therapist.get('location', '')
    
    try:
        safe_print(f"\n👤 Processing {index}/{total}: {name}")
        results = search_therapist(name, location)
        updated_therapist, changes = update_therapist_data(therapist, results)
        
        if changes:
            safe_print("\n✅ Updates made for {name}:")
            for change in changes:
                safe_print(f"  • {change}")
        else:
            safe_print(f"\n⚠️  No new information found for {name}")
            
        return index, updated_therapist, changes
        
    except Exception as e:
        safe_print(f"❌ Error processing therapist {name}: {e}")
        return index, therapist, []

def main():
    input_file = 'data.json'
    output_file = 'enriched_data.json'
    MAX_WORKERS = 100  # Number of concurrent threads
    
    print("\n🔍 Starting therapist data enrichment process")
    print("=" * 50)
    
    # Load data
    data = load_data(input_file)
    if not data or 'therapists' not in data:
        print("❌ No therapists data found")
        return
    
    total_therapists = len(data['therapists'])
    print(f"📋 Found {total_therapists} therapists to process\n")
    
    # Statistics tracking
    stats = {
        'processed': 0,
        'enriched': 0,
        'errors': 0,
        'total_emails_found': 0,
        'total_phones_found': 0
    }
    
    # Thread-safe stats updating
    stats_lock = threading.Lock()
    def update_stats(changes):
        with stats_lock:
            stats['processed'] += 1
            if changes:
                stats['enriched'] += 1
    
    # Create a queue for saving results
    save_queue = Queue()
    
    # File saving thread
    def save_worker():
        while True:
            save_data = save_queue.get()
            if save_data is None:  # Poison pill
                break
            try:
                with open(output_file, 'w') as f:
                    json.dump(save_data, f, indent=2)
            except Exception as e:
                safe_print(f"Error saving data: {e}")
            save_queue.task_done()
    
    # Start save worker thread
    save_thread = threading.Thread(target=save_worker)
    save_thread.start()
    
    # Process therapists with thread pool
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        # Create future to therapist mapping
        future_to_therapist = {
            executor.submit(
                process_single_therapist, 
                therapist, 
                i + 1, 
                total_therapists
            ): (i, therapist) 
            for i, therapist in enumerate(data['therapists'])
        }
        
        # Process completed futures with progress bar
        with tqdm.tqdm(total=total_therapists, desc="Processing therapists") as pbar:
            for future in concurrent.futures.as_completed(future_to_therapist):
                try:
                    index, updated_therapist, changes = future.result()
                    data['therapists'][index-1] = updated_therapist
                    update_stats(changes)
                    
                    # Queue save operation
                    save_queue.put(data.copy())
                    
                except Exception as e:
                    original_index, original_therapist = future_to_therapist[future]
                    safe_print(f"❌ Error processing {original_therapist.get('name', 'Unknown')}: {e}")
                    stats['errors'] += 1
                
                pbar.update(1)
    
    # Signal save worker to stop and wait for completion
    save_queue.put(None)
    save_thread.join()
    
    # Print final statistics
    print("\n📊 Final Statistics")
    print("=" * 50)
    print(f"Total therapists processed: {stats['processed']}/{total_therapists}")
    print(f"Therapists enriched with new data: {stats['enriched']}")
    print(f"Errors encountered: {stats['errors']}")
    print(f"\n✨ Processing complete! Results saved to {output_file}")

if __name__ == "__main__":
    main() 
