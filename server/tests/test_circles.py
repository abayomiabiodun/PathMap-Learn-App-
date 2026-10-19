import importlib.util
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

spec = importlib.util.spec_from_file_location('circles_api', Path(__file__).resolve().parents[1] / 'circles_api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class CirclesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.database = Path(self.temp.name) / 'test.sqlite3'
        self.service = api.CirclesService(self.database)
        self.alice = self.register('alice', 'web')
        self.bob = self.register('bob', 'web')
        self.carol = self.register('carol', 'data')

    def tearDown(self):
        self.temp.cleanup()

    def register(self, handle, path):
        return self.service.dispatch('POST', '/auth/register', {'handle': handle, 'password': 'Test-only-password-123', 'name': handle.title(), 'path': path})['token']

    def call(self, token, method, route, **data):
        return self.service.dispatch(method, route, data, token)

    def state(self, token):
        return self.call(token, 'GET', '/state')

    def invite_bob(self):
        bid = self.state(self.bob)['profile']['id']
        self.call(self.alice, 'POST', '/invites', learner=bid)
        invitation = self.state(self.bob)['invites'][0]
        self.call(self.bob, 'POST', f"/invites/{invitation['id']}/respond", accept=True)

    def publish(self, token, body=None, title='My learning project'):
        state = self.state(token)
        return self.call(token, 'POST', '/posts', circle=state['own_circle'], title=title, body=body or 'I built a useful small page and practised semantic HTML and accessible labels.', url='https://example.com/project')['id']

    def test_authentication_and_session_revocation(self):
        profile = self.state(self.alice)['profile']
        self.assertNotIn('salt', profile)
        self.assertNotIn('password_hash', profile)
        self.assertNotIn('password', profile)
        with self.assertRaises(api.ApiError):
            self.service.dispatch('GET', '/state', {}, '')
        with self.assertRaises(api.ApiError):
            self.service.dispatch('POST', '/auth/login', {'handle': 'alice', 'password': 'wrong-password'})
        logged = self.service.dispatch('POST', '/auth/login', {'handle': 'alice', 'password': 'Test-only-password-123'})['token']
        self.assertEqual(self.state(logged)['profile']['id'], profile['id'])
        self.call(logged, 'POST', '/auth/logout')
        with self.assertRaises(api.ApiError):
            self.state(logged)

    def test_same_interest_invites_require_recipient_consent(self):
        alice_state = self.state(self.alice)
        self.assertEqual([r['name'] for r in alice_state['learners']], ['Bob'])
        carol_id = self.state(self.carol)['profile']['id']
        with self.assertRaises(api.ApiError):
            self.call(self.alice, 'POST', '/invites', learner=carol_id)
        bob_id = self.state(self.bob)['profile']['id']
        self.call(self.alice, 'POST', '/invites', learner=bob_id)
        invitation = self.state(self.bob)['invites'][0]
        self.assertEqual(len(self.state(self.alice)['members']), 1)
        with self.assertRaises(api.ApiError):
            self.call(self.alice, 'POST', '/invites', learner=bob_id)
        with self.assertRaises(api.ApiError):
            self.call(self.alice, 'POST', f"/invites/{invitation['id']}/respond", accept=True)
        self.call(self.bob, 'POST', f"/invites/{invitation['id']}/respond", accept=True)
        self.assertEqual(len(self.state(self.alice)['members']), 2)
        self.assertEqual(self.state(self.alice)['invites'][0]['status'], 'accepted')

    def test_privacy_and_declined_invitations(self):
        self.call(self.bob, 'POST', '/profile', path='web', discoverable=False)
        self.assertEqual(self.state(self.alice)['learners'], [])
        with self.assertRaises(api.ApiError):
            self.call(self.alice, 'POST', '/invites', learner=self.state(self.bob)['profile']['id'])
        self.call(self.bob, 'POST', '/profile', path='web', discoverable=True)
        self.call(self.alice, 'POST', '/invites', learner=self.state(self.bob)['profile']['id'])
        invite = self.state(self.bob)['invites'][0]
        self.call(self.bob, 'POST', f"/invites/{invite['id']}/respond", accept=False)
        self.assertEqual(len(self.state(self.alice)['members']), 1)

    def test_mentor_offer_request_and_owned_response(self):
        self.call(self.bob, 'POST', '/mentor-offer', bio='I can help beginners practise HTML, CSS and accessible websites.', available=True)
        mentors = self.state(self.alice)['mentors']
        self.assertEqual([m['name'] for m in mentors], ['Bob'])
        self.assertEqual(self.state(self.carol)['mentors'], [])
        self.call(self.alice, 'POST', '/guidance', mentor=mentors[0]['id'], message='Please help me understand how to use semantic headings in my first page.')
        request = self.state(self.bob)['guidance'][0]
        self.assertEqual(self.state(self.carol)['guidance'], [])
        with self.assertRaises(api.ApiError):
            self.call(self.alice, 'POST', f"/guidance/{request['id']}/respond", accept=True, reply='A fake response')
        self.call(self.bob, 'POST', f"/guidance/{request['id']}/respond", accept=True, reply='I can help. Start by sharing your heading structure.')
        self.assertEqual(self.state(self.alice)['guidance'][0]['status'], 'accepted')
        self.call(self.bob, 'POST', '/mentor-offer', bio='I can help beginners practise HTML, CSS and accessible websites.', available=False)
        self.assertEqual(self.state(self.alice)['mentors'], [])

    def test_posts_are_circle_scoped_and_owned(self):
        post = self.publish(self.alice)
        self.assertEqual(self.state(self.bob)['posts'], [])
        self.invite_bob()
        self.assertEqual(self.state(self.bob)['posts'][0]['id'], post)
        self.assertEqual(self.state(self.carol)['posts'], [])
        with self.assertRaises(api.ApiError):
            self.call(self.bob, 'PATCH', f'/posts/{post}', title='Not mine', body='I should not be allowed to change another learner’s post.', url='')
        with self.assertRaises(api.ApiError):
            self.call(self.bob, 'DELETE', f'/posts/{post}')
        self.call(self.alice, 'PATCH', f'/posts/{post}', title='Corrected project', body='I corrected a mistake in my page and learned to add clearer labels.', url='')
        self.assertEqual(self.state(self.bob)['posts'][0]['title'], 'Corrected project')
        self.assertEqual(self.state(self.alice)['profile']['post_points'], 10)
        self.call(self.alice, 'DELETE', f'/posts/{post}')
        self.assertEqual(self.state(self.bob)['posts'], [])
        self.assertEqual(self.state(self.alice)['profile']['post_points'], 0)

    def test_duplicate_reposts_and_daily_point_cap(self):
        first = self.publish(self.alice)
        self.publish(self.alice, title='Same body, different heading')
        self.assertEqual(self.state(self.alice)['profile']['post_points'], 10)
        self.call(self.alice, 'DELETE', f'/posts/{first}')
        self.publish(self.alice)
        self.assertEqual(self.state(self.alice)['profile']['post_points'], 0)
        for index in range(5):
            self.publish(self.alice, body=f'Unique practice {index}: I built another project with useful explanations and reviewed what I learned.')
        # Deleted awards still use a daily slot; recreating them does not farm points.
        self.assertEqual(self.state(self.alice)['profile']['post_points'], 20)
        restored = api.CirclesService(self.database)
        self.assertEqual(restored.dispatch('GET', '/state', {}, self.alice)['profile']['post_points'], 20)

    def test_concurrent_post_awards_cannot_exceed_daily_cap(self):
        with ThreadPoolExecutor(max_workers=5) as pool:
            list(pool.map(lambda i: self.publish(self.alice, body=f'Concurrent unique work {i}: I practised a complete example and recorded the results carefully.'), range(8)))
        self.assertEqual(self.state(self.alice)['profile']['post_points'], 30)

    def test_invalid_posts_and_foreign_circle_cannot_publish(self):
        circle = self.state(self.alice)['own_circle']
        with self.assertRaises(api.ApiError):
            self.call(self.bob, 'POST', '/posts', circle=circle, title='Test', body='This is a long enough attempt to publish without membership.', url='')
        for title, body, url in [('x', 'short', ''), ('Title', 'A long enough project explanation to pass the body length check.', 'javascript:alert(1)')]:
            with self.assertRaises(api.ApiError):
                self.call(self.alice, 'POST', '/posts', circle=circle, title=title, body=body, url=url)
        self.assertEqual(self.state(self.alice)['posts'], [])


if __name__ == '__main__':
    unittest.main()
