import React from 'react'
import PropTypes from 'prop-types'
import { Grid, Message, Tab, Form } from 'semantic-ui-react'

import { formBody as bodyPropTypes } from '/components/createSchemaFormHoc/propTypes'
import { TextField as PlainTextField, withDebounce } from '/components/fields'
import handlerFor from '/helpers/handleSetFieldValue'
import { hasValue, filterPredicateErrors } from '/helpers/validation'
import PredicateEditor from './PredicateEditor/index.jsx'
import FieldsEditor from './FieldsEditor.jsx'
import { predicate as predicatePropTypes } from './propTypes.js'

const TextField = withDebounce(PlainTextField)

function FormBody({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  handleBlur,
  localize,
  locale,
  isEdit,
}) {
  const propsFor = key => ({
    name: key,
    value: values[key],
    touched: !!touched[key],
    errors: getFieldErrors(key),
    disabled: isSubmitting,
    onChange: handlerFor(setFieldValue),
    onBlur: handleBlur,
    localize,
  })

  const predicateProps = propsFor('predicate')
  const fieldsProps = propsFor('fields')

  const filteredPredicateErrors =
    hasValue(predicateProps.errors) && filterPredicateErrors(predicateProps.errors[0])

  const renderPredicateEditor = () => (
    <PredicateEditor
      value={values.predicate}
      isEdit={isEdit}
      onChange={value => setFieldValue('predicate', value)}
      localize={localize}
      locale={locale}
    />
  )

  const renderFieldsEditor = () => (
    <FieldsEditor
      value={values.fields}
      onChange={value => setFieldValue('fields', value)}
      localize={localize}
    />
  )

  return (
    <div>
      <br />
      <Grid>
        <Grid.Row>
          <Form.Group widths="equal" style={{ width: '100%' }}>
            <Form.Input
              {...propsFor('name')}
              label={localize('Name')}
              placeholder={localize('NameIsRequired')}
              required
              autoComplete="off"
            />
            <Form.Input
              {...propsFor('description')}
              label={localize('Description')}
              placeholder={localize('Description')}
              autoComplete="off"
            />
          </Form.Group>
        </Grid.Row>
        <Grid.Row
          as={Tab}
          panes={[
            { menuItem: localize('Predicate'), render: renderPredicateEditor },
            { menuItem: localize('Fields'), render: renderFieldsEditor },
          ]}
        />

        {(hasValue(predicateProps.errors) || hasValue(fieldsProps.errors)) && (
          <Message error>
            <Message.List>
              {hasValue(predicateProps.errors) && (
                <Message.Item content={filteredPredicateErrors.map(localize)} />
              )}
              {hasValue(fieldsProps.errors) && (
                <Message.Item content={fieldsProps.errors.map(localize)} />
              )}
            </Message.List>
          </Message>
        )}
      </Grid>
    </div>
  )
}

const { arrayOf, number, shape, string } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shape({
    name: string.isRequired,
    description: string,
    fields: arrayOf(number).isRequired,
    predicate: predicatePropTypes.isRequired,
  }).isRequired,
}

export default FormBody
