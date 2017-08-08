import React from 'react'
import { shape, func, node } from 'prop-types'
import { Link } from 'react-router'
import { Icon } from 'semantic-ui-react'

import Form from 'components/SchemaForm'
import styles from './styles.pcss'

const StatUnitForm = ({ formData, schema, localize, onChange, onSubmit, children }) => (
  <Form
    value={formData}
    onChange={onChange}
    onSubmit={onSubmit}
    schema={schema}
    className={styles['statunit-form']}
  >
    {children}
    <br key="stat_unit_form_br" />
    <Form.Button
      as={Link}
      to="/statunits"
      content={localize('Back')}
      icon={<Icon size="large" name="chevron left" />}
      floated="left"
      size="small"
      color="grey"
      type="button"
      key="stat_unit_form_back_btn"
    />
    <Form.Trigger>
      {({ messages }) => (
        <Form.Button
          key="stat_unit_form_submit_btn"
          content={localize('Submit')}
          disabled={!!Object.entries(messages).length}
          type="submit"
          floated="right"
          primary
        />
      )}
    </Form.Trigger>
  </Form>
)

StatUnitForm.propTypes = {
  children: node.isRequired,
  formData: shape({}).isRequired,
  schema: shape({}).isRequired,
  localize: func.isRequired,
  onChange: func.isRequired,
  onSubmit: func.isRequired,
}

export default StatUnitForm
