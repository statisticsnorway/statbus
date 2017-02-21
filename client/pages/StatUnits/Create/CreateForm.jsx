import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import getField from 'components/getField'
import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import styles from './styles.pcss'

const CreateForm = ({
  statUnitModel, type, errors,
  handleSubmit, localize, changeType,
}) => {
  const statUnitTypeOptions =
    [...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) }))

  const handleTypeEdit = (e, { value }) => {
    if (type !== value) changeType(value)
  }
  const fields = statUnitModel.properties.map(x => getField(x, errors))
  return (
    <div className={styles.edit}>
      <Form.Select
        name="type"
        options={statUnitTypeOptions}
        value={type}
        onChange={handleTypeEdit}
      />
      <Form className={styles.form} onSubmit={handleSubmit} error>
        {fields}
        <br />
        <Button className={styles.sybbtn} type="submit" primary>
          {localize('Submit')}
        </Button>
      </Form>
    </div>
  )
}

const { func } = React.PropTypes

CreateForm.propTypes = {
  handleSubmit: func.isRequired,
  changeType: func.isRequired,
  localize: func.isRequired,
}

export default wrapper(CreateForm)
