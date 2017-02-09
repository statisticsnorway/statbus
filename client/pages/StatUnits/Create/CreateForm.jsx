import React from 'react'
import { Button, Form } from 'semantic-ui-react'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import mapPropertyToComponent from 'helpers/componentMapper'
import styles from './styles.pcss'

const CreateForm = ({ handleSubmit, localize, statUnitModel, type, errors, changeType }) => {
  const statUnitTypeOptions =
    [...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) }))

  const handleTypeEdit = (e, { value }) => changeType(value)
  const inner = statUnitModel.properties.map(x => mapPropertyToComponent(x, errors))
  return (
    <div className={styles.edit}>
      <Form.Select
        name="type"
        options={statUnitTypeOptions}
        value={type}
        onChange={handleTypeEdit}
      />
      <Form className={styles.form} onSubmit={handleSubmit} error>
        {inner}
        <br />
        <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
      </Form>
    </div>
  )
}

const { func } = React.PropTypes

CreateForm.propTypes = {
  handleSubmit: func.isRequired,
  changeType: func.isRequired,
}

export default wrapper(CreateForm)
