import React from 'react'
import { Form, TextArea } from 'semantic-ui-react'

import { DateTimeField } from '/components/fields'

const Create = ({ localize, item, actions: { editQueueItem, submitItem } }) => {
  const handleChange = (_, { name, value }) => editQueueItem({ name, value })

  const handleSubmit = (e) => {
    e.preventDefault()
    submitItem(item)
  }
  return (
    <Form onSubmit={handleSubmit}>
      <h2>{localize('EnqueueNewItem')}</h2>
      <DateTimeField
        onChange={handleChange}
        name="dateFrom"
        value={item.dateFrom}
        label="DateFrom"
        localize={localize}
      />
      <DateTimeField
        onChange={handleChange}
        name="dateTo"
        value={item.dateTo}
        label="DateTo"
        localize={localize}
      />
      <Form.Input
        control={TextArea}
        label={localize('Comment')}
        value={item.comment}
        name="comment"
        onChange={handleChange}
      />
      <Form.Button
        icon="checkmark"
        content={localize('ButtonSave')}
        type="submit"
        floated="right"
        primary
      />
    </Form>
  )
}

export default Create
