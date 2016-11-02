import React from 'react'
import { Button, Form, Message } from 'semantic-ui-react'

export default ({ roles, submitUser, message, status }) => {
  const handleSubmit = (e, serialized) => {
    e.preventDefault()
    submitRole(serialized)
  }
  return (
    <Form onSubmit={handleSubmit}>
      <Form.Field>
        <label htmlFor="userNameInput">User name</label>
        <input
          id="userNameInput"
          placeholder="e.g. Robert Diggs"
          name="name"
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="userEmailInput">User email</label>
        <input
          id="userEmailInput"
          placeholder="e.g. robertdiggs@site.domain"
          name="email"
          type="email"
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="userLoginInput">User login</label>
        <input
          id="userLoginInput"
          placeholder="e.g. rdiggs"
          name="login"
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="userPasswordInput">User password</label>
        <input
          id="userPasswordInput"
          placeholder="type strong password here"
          name="password"
          type="password"
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="userConfirmPasswordInput">User confirmPassword</label>
        <input
          id="userConfirmPasswordInput"
          placeholder="e.g. robertdiggs@site.domain"
          name="confirmPassword"
          type="password"
        />
      </Form.Field>
      <Form.Field>
        <label htmlFor="userDescriptionInput">Description</label>
        <input
          id="userDescriptionInput"
          placeholder="e.g. very famous NSO employee"
          name="description"
        />
      </Form.Field>
      <Button type="submit" primary>Submit</Button>
      {message && <Message content={message} />}
    </Form>
  )
}
