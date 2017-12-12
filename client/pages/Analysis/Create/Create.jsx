import React from 'react'
import { func, shape, arrayOf, number, string } from 'prop-types'
import { Form, TextArea } from 'semantic-ui-react'
import { getDate, dateFormat, toUtc } from 'helpers/dateHelper'
import DatePicker from 'react-datepicker'

const Create = ({ localize, item, actions: { editQueueItem, submitItem } }) => {
  const handleDatePickerChange = name => (value) => {
    editQueueItem({ name, value: value === null ? item[name] : toUtc(value) })
  }

  const handleChange = name => ({ target: { value } }) => editQueueItem({ name, value })

  const handleSubmit = (e) => {
    e.preventDefault()
    submitItem(item)
  }
  return (
    <Form onSubmit={handleSubmit}>
      <h2>{localize('EnqueueNewItem')}</h2>

      <div className="field datepicker">
        <label htmlFor="dateFrom">{localize('DateFrom')}</label>
        <DatePicker
          selected={getDate(item.dateFrom)}
          onChange={handleDatePickerChange('dateFrom')}
          dateFormat={dateFormat}
          className="ui input"
          type="number"
          name="dateFrom"
          value={item.dateFrom}
          id="dateFrom"
        />
      </div>
      <div className="field datepicker">
        <label htmlFor="dateTo">{localize('DateTo')}</label>
        <DatePicker
          selected={getDate(item.dateTo)}
          onChange={handleDatePickerChange('dateTo')}
          dateFormat={dateFormat}
          className="ui input"
          type="number"
          name="dateTo"
          value={item.dateTo}
          id="dateTo"
        />
      </div>
      <Form.Input
        control={TextArea}
        label={localize('Comment')}
        value={item.comment}
        onChange={handleChange('comment')}
        required
      />
      <Form.Button
        icon="checkmark"
        content={localize('Save')}
        type="submit"
        floated="right"
        primary
      />
    </Form>
  )
}
export default Create
